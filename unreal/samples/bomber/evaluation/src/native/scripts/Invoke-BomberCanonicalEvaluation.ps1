[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CandidateProject,
    [Parameter(Mandatory)][string]$EngineRoot,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$')][string]$RunId = ('run-' + [guid]::NewGuid().ToString('N')),
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$')][string]$CandidateId,
    [string]$D6RunPath,
    [string]$VlmModel,
    [string]$VlmBaseUrl,
    [ValidateRange(1,240)][int]$VlmTimeoutSeconds = 240,
    [switch]$DiagnosticsOnly,
    [switch]$SkipBuild,
    [ValidateRange(1,5)][int]$StableSamples = 2,
    [ValidateRange(60000,600000)][int]$SessionTimeoutMs = 60000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:CommonModulePath = Join-Path (Split-Path -Parent $PSCommandPath) 'BomberEvaluator.Common.psm1'
Import-Module $script:CommonModulePath -Force
Import-Module (Join-Path (Split-Path -Parent $PSCommandPath) 'BomberObservation.psm1') -Force
Import-Module (Join-Path (Split-Path -Parent $PSCommandPath) 'BomberNativeCapture.psm1') -Force

function Write-JsonFile {
    param([Parameter(Mandatory)][AllowNull()]$Value, [Parameter(Mandatory)][string]$Path)
    $parent = Split-Path -Parent $Path
    if ($parent) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    [IO.File]::WriteAllText($Path, ((ConvertTo-Json -InputObject $Value -Depth 100).Replace("`r`n", "`n") + "`n"), [Text.UTF8Encoding]::new($false))
}

function Get-RelativeEvidencePath([string]$Path) {
    return [IO.Path]::GetRelativePath($script:OutputFull, [IO.Path]::GetFullPath($Path)).Replace('\', '/')
}

function Save-Receipt($Value, [string]$Name) {
    $path = Join-Path $script:OutputFull "receipts/$Name.json"
    Write-JsonFile -Value $Value -Path $path
    return Get-RelativeEvidencePath $path
}

function Save-State($Value, [string]$Name) {
    $path = Join-Path $script:OutputFull "states/$Name.json"
    Write-JsonFile -Value $Value -Path $path
    return Get-RelativeEvidencePath $path
}

function Set-Checkpoint {
    param(
        [string]$Id,
        [ValidateSet('pass','fail','unreachable')][string]$Verdict,
        [string]$Detail,
        [string[]]$Evidence = @(),
        [string]$ReasonCode,
        [string]$FirstFailure
    )
    $item = $script:VerdictsById[$Id]
    if ($null -eq $item) { throw "Unknown checkpoint: $Id" }
    $item.verdict = $Verdict
    $item.detail = $Detail
    $item.evidence = @($Evidence | Where-Object { $_ } | Sort-Object -Unique)
    $item.reason_code = if ($Verdict -eq 'pass') { $null } elseif ($ReasonCode) { $ReasonCode } elseif ($Verdict -eq 'unreachable') { 'CANDIDATE_PREREQUISITE_UNREACHABLE' } else { 'CANDIDATE_REQUIREMENT_FAILED' }
    $item.attribution = if ($Verdict -eq 'pass') { $null } else { 'candidate' }
    $item.first_failure = if ($Verdict -eq 'pass') { $null } elseif (-not [string]::IsNullOrWhiteSpace($FirstFailure)) { $FirstFailure } elseif (@($item.evidence).Count -gt 0) { [string]$item.evidence[0] } else { "checkpoint:$Id" }
    $item.score_impact = if ($Verdict -eq 'pass') { 'full_credit' } else { 'checkpoint_zero' }
}

function Set-UnresolvedDynamic {
    param(
        [ValidateSet('fail','unreachable')][string]$Verdict,
        [string]$Detail,
        [string[]]$Dimensions = @('D2','D3','D4','D5'),
        [string]$ReasonCode,
        [string]$FirstFailure
    )
    foreach ($item in $script:Verdicts) {
        if ($item.dimension -in $Dimensions -and $null -eq $item.verdict) {
            Set-Checkpoint -Id $item.checkpoint_id -Verdict $Verdict -Detail $Detail -ReasonCode $ReasonCode -FirstFailure $FirstFailure
        }
    }
}

function Get-ProjectIdentity([string]$ProjectRoot) {
    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            $bytes = [Text.UTF8Encoding]::new($false).GetBytes("missing-project-root:`n$ProjectRoot")
            return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
        }
        finally { $sha.Dispose() }
    }
    $lines = foreach ($file in Get-ChildItem -LiteralPath $ProjectRoot -File -Recurse | Where-Object {
        $_.FullName -notmatch '[\\/](Binaries|DerivedDataCache|Intermediate|Saved|\.vs|\.idea)[\\/]'
    } | Sort-Object FullName) {
        $relative = [IO.Path]::GetRelativePath($ProjectRoot, $file.FullName).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$relative`t$hash`t$($file.Length)"
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($lines -join "`n"))
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Test-Cell($Cell, [int]$X, [int]$Y) {
    return $null -ne $Cell -and [int]$Cell.x -eq $X -and [int]$Cell.y -eq $Y
}

function Get-Player($State, [string]$Id) {
    return @($State.game_state.players | Where-Object object_id -eq $Id) | Select-Object -First 1
}

function Get-Crate($State, [int]$X, [int]$Y) {
    return @($State.game_state.crates | Where-Object { Test-Cell $_.cell $X $Y }) | Select-Object -First 1
}

function Get-Powerup($State, [string]$Kind) {
    return @($State.game_state.powerups | Where-Object kind -eq $Kind) | Select-Object -First 1
}

function Test-BomberEnvelope($State, [switch]$AllowProviderNotReady) {
    $validation = Test-BomberStateEnvelope -State $State -ExpectedProcessToken $script:ProcessToken -ExpectedProcessId $script:ProcessId `
        -AllowProviderNotReady:$AllowProviderNotReady -PreviousState $script:LastAcceptedState
    $script:LastStateDiagnostic = $validation
    return [bool]$validation.valid
}

function Read-BomberState([switch]$AllowProviderNotReady) {
    if (-not (Test-Path -LiteralPath $script:GameStatePath -PathType Leaf)) { return $null }
    try {
        $item = Get-Item -LiteralPath $script:GameStatePath
        if ((([DateTime]::UtcNow - $item.LastWriteTimeUtc).TotalMilliseconds) -gt $script:StateMaxAgeMs) {
            $script:LastStateDiagnostic = [pscustomobject][ordered]@{valid=$false;code='STATE_STALE'}
            return $null
        }
        $state = Get-Content -LiteralPath $script:GameStatePath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
        if (-not (Test-BomberEnvelope -State $state -AllowProviderNotReady:$AllowProviderNotReady)) { return $null }
        $script:LastAcceptedState = $state
        return $state
    }
    catch {
        $script:LastStateDiagnostic = [pscustomobject][ordered]@{valid=$false;code='STATE_READ_OR_PARSE_FAILED'}
        return $null
    }
}

function Wait-BomberState {
    param(
        [scriptblock]$Condition,
        [double]$TimeoutSeconds,
        [string]$SaveAs,
        [switch]$AllowProviderNotReady,
        [ValidateRange(1,5)][int]$RequiredSamples = $script:StableSamples
    )
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $matches = 0
    $lastMatch = $null
    $samples = [Collections.Generic.List[object]]::new()
    try {
    do {
        $state = Read-BomberState -AllowProviderNotReady:$AllowProviderNotReady
        if ($null -ne $state) { $samples.Add($state) }
        if ($null -ne $state -and (& $Condition $state)) {
            if ($null -ne $lastMatch -and [string]$state.round_id -eq [string]$lastMatch.round_id) { ++$matches } else { $matches = 1 }
            $lastMatch = $state
            if ($matches -ge $RequiredSamples) {
                if ($SaveAs) { [void](Save-State -Value $state -Name $SaveAs) }
                return $state
            }
        }
        elseif ($null -eq $state -and $null -ne $script:LastStateDiagnostic -and
            $script:LastStateDiagnostic.PSObject.Properties.Name -contains 'code' -and
            [string]$script:LastStateDiagnostic.code -eq 'STATE_SNAPSHOT_REPEATED') {
            # Keep prior matches, but never count the same snapshot twice.
        }
        else {
            $matches = 0
            $lastMatch = $null
        }
        Start-Sleep -Milliseconds $script:StatePollMs
    } while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    return $null
    }
    finally {
        if ($SaveAs) { Write-JsonFile -Value @($samples) -Path (Join-Path $script:OutputFull "states/$SaveAs-samples.json") }
    }
}

function Invoke-Press([string]$Key, [string]$Name, [int]$DurationMs = 45) {
    $receipt = Invoke-UnrealPressKey -Session $script:Session -Key $Key -DurationMs $DurationMs
    [void](Save-Receipt -Value $receipt -Name $Name)
    if ($receipt.status -ne 'ok') { throw "executor_input_fault:$Name" }
    Start-Sleep -Milliseconds 35
    return $receipt
}

function Invoke-Sequence([string[]]$Keys, [string]$Prefix) {
    $index = 0
    foreach ($key in $Keys) {
        ++$index
        [void](Invoke-Press -Key $key -Name ("$Prefix-$index-$key"))
    }
}

function Save-Capture([string]$Name) {
    $path = Join-Path $script:OutputFull "captures/$Name.png"
    try {
        [void](Resolve-BomberSafePath -Root (Join-Path $script:OutputFull 'captures') -Path $path)
        $receipt = Save-BomberNativeCapture -CaptureRoot (Join-Path $script:OutputFull "captures") -Name $Name -ProcessToken $script:ProcessToken -ProcessId $script:ProcessId
        [void](Save-Receipt -Value $receipt -Name "capture-$Name")
        $validReceipt = $receipt.status -eq 'ok' -and $null -ne $receipt.result -and
            [int]$receipt.result.width -eq [int]$script:Config.robustness.capture_width -and
            [int]$receipt.result.height -eq [int]$script:Config.robustness.capture_height
        if ($validReceipt -and (Test-Path -LiteralPath $path -PathType Leaf) -and
            (Get-Item -LiteralPath $path).Length -ge [int64]$script:Config.robustness.capture_min_bytes) {
            $relative = Get-RelativeEvidencePath $path
            $script:CaptureEvidence.Add($relative)
            $metrics = Measure-CaptureSceneHealth -Path $path -Name $Name
            $script:CaptureVisualHealth[$Name] = $metrics
            return $relative
        }
    }
    catch {
        $message = [string]$_.Exception.Message
        # A capture transaction or image-analysis dependency failure belongs to
        # the evaluator/host, not to the candidate's visual score.  Preserve
        # malformed/blank candidate frames as ordinary candidate evidence
        # failures, but surface executor/environment faults to the outer
        # attribution policy so the run is not silently scored.
        if ($message -match '(?i)^(measurement_fault:|executor_|environment_|unsupported_|capture_visual_measurement_fault:.*(Unable to find type|cannot find type|assembly|System\.Drawing|GDI\+|not supported))') {
            throw $message
        }
        $script:CaptureVisualHealth[$Name] = [pscustomobject][ordered]@{scene_visible=$false;status='capture_error';diagnostic=$message}
    }
    return $null
}

function Measure-CaptureSceneHealth {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    $bitmap = $null
    try {
        Add-Type -AssemblyName System.Drawing.Common -ErrorAction SilentlyContinue
        $bitmap = [Drawing.Bitmap]::new($Path)
        if ($bitmap.Width -ne [int]$script:Config.robustness.capture_width -or $bitmap.Height -ne [int]$script:Config.robustness.capture_height) { throw 'capture_dimensions_changed' }
        $count = 0; $nonDark = 0; $sum = 0.0; $sumSquares = 0.0
        for ($y = 86; $y -le 620; $y += 18) {
            for ($x = 64; $x -le 1216; $x += 18) {
                $pixel = $bitmap.GetPixel($x, $y)
                $luminance = 0.2126 * $pixel.R + 0.7152 * $pixel.G + 0.0722 * $pixel.B
                if ($luminance -ge 18.0) { ++$nonDark }
                $sum += $luminance; $sumSquares += $luminance * $luminance; ++$count
            }
        }
        $mean = $sum / $count
        $standardDeviation = [Math]::Sqrt([Math]::Max(0.0, ($sumSquares / $count) - ($mean * $mean)))
        $nonDarkRatio = [double]$nonDark / [double]$count
        $metrics = [pscustomobject][ordered]@{
            capture = "captures/$Name.png"
            sample_region = [ordered]@{left=64;top=86;right=1216;bottom=620;step=18}
            sample_count = $count
            non_dark_ratio = [Math]::Round($nonDarkRatio, 4)
            mean_luminance = [Math]::Round($mean, 2)
            luminance_standard_deviation = [Math]::Round($standardDeviation, 2)
            scene_visible = ($nonDarkRatio -ge 0.22 -and $standardDeviation -ge 10.0)
        }
        Write-JsonFile $metrics (Join-Path $script:OutputFull "receipts/capture-$Name-visual.json")
        return $metrics
    }
    catch { throw "capture_visual_measurement_fault:${Name}:$($_.Exception.Message)" }
    finally { if ($bitmap) { $bitmap.Dispose() } }
}

function Test-CaptureSceneVisible([string]$Name) {
    return $script:CaptureVisualHealth.ContainsKey($Name) -and $script:CaptureVisualHealth[$Name].scene_visible -eq $true
}

function Wait-Cell([string]$PlayerId, [int]$X, [int]$Y, [string]$SaveAs, [double]$TimeoutSeconds = 1.0) {
    return Wait-BomberState -TimeoutSeconds $TimeoutSeconds -SaveAs $SaveAs -Condition {
        param($state) Test-Cell (Get-Player $state $PlayerId).cell $X $Y
    }
}

function Press-ToCell([string]$Key, [string]$PlayerId, [int]$X, [int]$Y, [string]$Name) {
    [void](Invoke-Press -Key $Key -Name $Name)
    return Wait-Cell -PlayerId $PlayerId -X $X -Y $Y -SaveAs $Name
}

function Invoke-Restart([string]$Name) {
    $before = Read-BomberState
    $oldRound = if ($before) { [string]$before.round_id } else { '' }
    [void](Invoke-Press -Key R -Name $Name)
    return Wait-BomberState -TimeoutSeconds 2.0 -SaveAs "$Name-state" -Condition {
        param($state) [string]$state.round_id -cne $oldRound -and [string]$state.game_state.phase -ceq 'countdown'
    }
}

function Measure-HoldToCell {
    param([string]$Key, [string]$PlayerId, [int]$X, [int]$Y, [string]$Name, [double]$TimeoutSeconds = 2.0, [switch]$NoRefinement)
    $samples = [Collections.Generic.List[object]]::new()
    $before = Wait-BomberState -Condition {param($s) $true} -TimeoutSeconds 1 -RequiredSamples 1
    if ($before) { $samples.Add($before) }
    $start = Start-UnrealKeyHold -Session $script:Session -Key $Key
    if ($start.status -ne 'ok') { throw "executor_input_fault:$Name-start" }
    $state = $null
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        do {
            $sample = Read-BomberState
            if ($sample) {
                $samples.Add($sample)
                if (Test-Cell (Get-Player $sample $PlayerId).cell $X $Y) { $state=$sample; break }
            }
            Start-Sleep -Milliseconds 10
        } while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    }
    finally {
        $stop = Stop-UnrealKeyHold -Session $script:Session -Key $Key -Cleanup
        [void](Save-Receipt -Value $start -Name "$Name-start")
        [void](Save-Receipt -Value $stop -Name "$Name-stop")
        Write-JsonFile -Value @($samples) -Path (Join-Path $script:OutputFull "states/$Name-samples.json")
    }
    if ($stop.status -ne 'ok') { throw "executor_input_fault:$Name-stop" }
    if ($state) { [void](Save-State $state $Name) }
    $isSkate=$before -and [int](Get-Player $before $PlayerId).resources.skate -eq 1
    $measurement=Measure-BomberMovementSamples -Samples @($samples) -PlayerId $PlayerId -MinimumMs $(if($isSkate){100}else{160}) -MaximumMs $(if($isSkate){130}else{200})
    [void](Save-Receipt $measurement "$Name-measurement")
    if ($measurement.status -eq 'measurement_invalid' -and -not $NoRefinement -and $state -and $before) {
        # Same clear corridor, same movement tier, normal input only. Intersect
        # every measured bracket; never select the most favorable trial.
        $origin = (Get-Player $before $PlayerId).cell
        $reverse = @{W='S';S='W';A='D';D='A';Up='Down';Down='Up';Left='Right';Right='Left'}[$Key]
        $trials = [Collections.Generic.List[object]]::new()
        $trials.Add($measurement)
        [void](Save-Receipt $measurement "$Name-first-measurement")
        for ($trial=1; $trial -le 3 -and $measurement.status -eq 'measurement_invalid'; $trial++) {
            $back = Measure-HoldToCell $reverse $PlayerId $origin.x $origin.y "$Name-refine-$trial-back" $TimeoutSeconds -NoRefinement
            $forward = Measure-HoldToCell $Key $PlayerId $X $Y "$Name-refine-$trial-forward" $TimeoutSeconds -NoRefinement
            if (-not $back.state -or -not $forward.state -or
                $back.state.process_token -cne $before.process_token -or $forward.state.process_token -cne $before.process_token -or
                $back.state.round_id -cne $before.round_id -or $forward.state.round_id -cne $before.round_id -or
                [int](Get-Player $back.state $PlayerId).resources.skate -ne [int](Get-Player $before $PlayerId).resources.skate -or
                [int](Get-Player $forward.state $PlayerId).resources.skate -ne [int](Get-Player $before $PlayerId).resources.skate) {
                $measurement = [pscustomobject]@{status='unreachable';pass=$false;interval_estimate_ms=$null;reason='candidate_did_not_repeat_clear_corridor'}
                break
            }
            $state = $forward.state
            foreach ($leg in @($back,$forward)) {
                if ($leg.measurement.status -in @('measured','measurement_invalid')) { $trials.Add($leg.measurement) }
            }
            $measurement = Merge-BomberMovementMeasurements -Measurements @($trials) -MinimumMs $(if($isSkate){100}else{160}) -MaximumMs $(if($isSkate){130}else{200})
        }
        [void](Save-Receipt $measurement "$Name-measurement")
    }
    if ($measurement.status -eq 'measurement_invalid' -and -not $NoRefinement) { throw "measurement_fault:${Name}:insufficient_temporal_resolution" }
    return [pscustomobject]@{ state = $state; measurement = $measurement }
}

function Save-SemanticCapture {
    param([string]$Name, [string]$StateId, $Before, [scriptblock]$Condition, $ChainExpectation=$null)
    if ($null -eq $Before -or -not (& $Condition $Before)) { return $null }
    # Capture at the first accepted transient sample, never after a failed wait.
    $capture = Save-Capture $Name
    if (-not $capture) { return $null }
    $native=Get-Content -LiteralPath (Join-Path $script:OutputFull "captures/$Name.native.json") -Raw|ConvertFrom-Json
    $after = Wait-BomberState -Condition {param($s) [double]$s.monotonic_ms -ge [double]$native.monotonic_ms} -TimeoutSeconds 0.35 -RequiredSamples 1
    if ($null -eq $after -or $Before.process_token -cne $after.process_token -or $Before.round_id -cne $after.round_id -or -not (& $Condition $after)) {
        throw "measurement_fault:${Name}:capture_missed_semantic_window"
    }
    $path=Join-Path $script:OutputFull "captures/$Name.png"
    $proof=[ordered]@{schema_version='1.0.0';state_id=$StateId;status='bound';candidate_identity_sha256=$candidateIdentity;capture_sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant();before=$Before;after=$after;native_capture=$native;chain_expectation=$ChainExpectation}
    Write-JsonFile $proof ([IO.Path]::ChangeExtension($path,'.semantic.json'))
    return $capture
}

function Test-CleanRound($State, [string]$ExpectedPhase = 'countdown') {
    if ($null -eq $State -or $State.provider_ready -ne $true -or [string]$State.game_state.phase -cne $ExpectedPhase) { return $false }
    $p1 = Get-Player $State 'player_1'; $p2 = Get-Player $State 'player_2'
    return (Test-Cell $p1.cell $script:ExpectedPlayer1Start.x $script:ExpectedPlayer1Start.y) -and
        (Test-Cell $p2.cell $script:ExpectedPlayer2Start.x $script:ExpectedPlayer2Start.y) -and
        $p1.alive -eq $true -and $p2.alive -eq $true -and
        [int]$p1.resources.bombs_available -eq 1 -and [int]$p1.resources.bomb_capacity -eq 1 -and [int]$p1.resources.fire -eq 2 -and [int]$p1.resources.skate -eq 0 -and
        [int]$p2.resources.bombs_available -eq 1 -and [int]$p2.resources.bomb_capacity -eq 1 -and [int]$p2.resources.fire -eq 2 -and [int]$p2.resources.skate -eq 0 -and
        @($State.game_state.crates | Where-Object state -eq 'present').Count -eq 15 -and @($State.game_state.powerups | Where-Object state -eq 'hidden').Count -eq 3 -and
        @($State.game_state.bombs).Count -eq 0 -and @($State.game_state.explosion_cells).Count -eq 0
}

function Test-AssetBindings($State) {
    if ($null -eq $State) { return $false }
    $expected = [ordered]@{
        character_mesh='/BlockoutMap/BlockoutMap/Characters/Mannequins/Meshes/SKM_Quinn_Simple'; player_1_material='/BlockoutMap/BlockoutMap/Characters/Mannequins/Materials/Quinn/MI_Quinn_01'; player_2_material='/BlockoutMap/BlockoutMap/Characters/Mannequins/Materials/Quinn/MI_Quinn_02'; idle_animation='/BlockoutMap/BlockoutMap/Animations/MM_Manny_Idle'; wall_mesh='/BlockoutMap/BlockoutMap/Meshes/SM_BlockoutMap_Wall'; crate_mesh='/BlockoutMap/BlockoutMap/Meshes/SM_BlockoutMap_Box'; bomb_powerup_mesh='/BlockoutMap/BlockoutMap/Meshes/SM_BlockoutMap_Powerup_Bomb'; fire_powerup_mesh='/BlockoutMap/BlockoutMap/Meshes/SM_BlockoutMap_Powerup_Fire'; skate_powerup_mesh='/BlockoutMap/BlockoutMap/Meshes/SM_BlockoutMap_Powerup_Skate'; bomb_mesh='/Game/Bomber/Meshes/SM_Bomb'; player_marker_mesh='/Game/Bomber/Meshes/SM_PlayerArrowStart'
    }
    foreach ($pair in $expected.GetEnumerator()) {
        if ([string]$State.game_state.asset_bindings.($pair.Key) -cne [string]$pair.Value) { return $false }
    }
    return $true
}

function Test-CandidateAssetKit {
    $manifestPath = Join-Path $script:TaskRoot 'input/ASSET_MANIFEST.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return $false }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
    foreach ($asset in @($manifest.assets)) {
        $assetPath = [string]$asset.path
        if (-not $assetPath.StartsWith('project/', [StringComparison]::Ordinal) -or $assetPath.Contains('..')) { return $false }
        $relative = $assetPath.Substring('project/'.Length).Replace('/', [IO.Path]::DirectorySeparatorChar)
        try {
            $candidate = Resolve-BomberSafePath -Root $script:ProjectRoot -Path (Join-Path $script:ProjectRoot $relative) -RequireLeaf
            $source = Resolve-BomberSafePath -Root (Join-Path $script:TaskRoot 'input/project') -Path (Join-Path (Join-Path $script:TaskRoot 'input/project') $relative) -RequireLeaf
            if ((Get-BomberSha256 $candidate) -cne (Get-BomberSha256 $source)) { return $false }
        }
        catch { return $false }
    }
    return $true
}

function Get-TerminalFingerprint($State) {
    if ($null -eq $State) { return $null }
    $game = $State.game_state
    return ([ordered]@{
        phase = [string]$game.phase
        match_remaining_ms = [double]$game.match_remaining_ms
        players = $game.players
        bombs = $game.bombs
        explosion_cells = $game.explosion_cells
        crates = $game.crates
        powerups = $game.powerups
        terminal_text = [string]$game.feedback.terminal_text
    } | ConvertTo-Json -Depth 40 -Compress)
}

function Test-ExistingBomberBuild {
    if (-not (Test-Path -LiteralPath (Join-Path $script:ProjectRoot 'Binaries/Win64') -PathType Container)) { return $false }
    $artifacts = @(Get-ChildItem -LiteralPath (Join-Path $script:ProjectRoot 'Binaries/Win64') -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^BomberStarter(Editor)?([-.].*)?\.(dll|exe|target|modules)$' })
    if ($artifacts.Count -eq 0) { return $false }
    # A skipped build is only valid when an existing target is newer than the
    # descriptor and at least one source file. This prevents SkipBuild from
    # silently converting a missing build into a D1 pass.
    $inputs = @($CandidateFull) + @(Get-ChildItem -LiteralPath (Join-Path $script:ProjectRoot 'Source') -File -Recurse -ErrorAction SilentlyContinue)
    $newestInput = @($inputs | Where-Object { $_ } | ForEach-Object { if ($_ -is [IO.FileInfo]) { $_ } else { Get-Item -LiteralPath $_ } } | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
    if ($null -eq $newestInput) { return $false }
    return @($artifacts | Where-Object LastWriteTimeUtc -ge $newestInput.LastWriteTimeUtc).Count -gt 0
}

function Get-StartFaultClassification([string]$Code, [object]$StartResult) {
    $codeLower = ([string]$Code).ToLowerInvariant()
    $domain = if ($StartResult -and $StartResult.fault) { [string]$StartResult.fault.domain } else { '' }
    if ($domain -in @('environment','executor','unsupported') -or
        $codeLower -match 'lease|cursor|input_state|job_|native|engine|foreground|window_discovery|path_|argument_|process_token|state_path|platform|unsupported') {
        return 'infrastructure'
    }
    if ($codeLower -match 'process_exited|target_process|first_frame|stable_visible|game_window|launch|start|timeout|crash|map|module|asset|state') {
        return 'candidate'
    }
    return 'infrastructure'
}

$ScriptRoot = Split-Path -Parent $PSCommandPath
$preflightError = $null
try {
    $EvaluatorRoot = [IO.Path]::GetFullPath((Join-Path $ScriptRoot '..'))
    $TaskRoot = [IO.Path]::GetFullPath((Join-Path $EvaluatorRoot '..'))
    $RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $TaskRoot '../..'))
    $CandidateFull = [IO.Path]::GetFullPath($CandidateProject)
    $ProjectRoot = Split-Path -Parent $CandidateFull
    $OutputFull = [IO.Path]::GetFullPath($OutputDirectory)
    $EngineFull = [IO.Path]::GetFullPath($EngineRoot)
    $script:TaskRoot = $TaskRoot; $script:ProjectRoot = $ProjectRoot; $script:OutputFull = $OutputFull
    $script:Config = Get-BomberEvaluatorConfig -EvaluatorRoot $EvaluatorRoot
    $script:StableSamples = $StableSamples
    $script:PublicBinding = Get-BomberPublicBinding -TaskRoot $TaskRoot
    $publicManifest = $script:PublicBinding.manifest
    $publicLayoutPath = $script:PublicBinding.layout_path
    $publicLayout = Get-Content -LiteralPath $publicLayoutPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 30
    $script:ExpectedPlayer1Start = @($publicLayout.players | Where-Object slot -eq 1)[0]
    $script:ExpectedPlayer2Start = @($publicLayout.players | Where-Object slot -eq 2)[0]
    $script:ExpectedCrateCells = @($publicLayout.crates | ForEach-Object { "$($_.x),$($_.y)" } | Sort-Object)
    if (@($script:ExpectedCrateCells).Count -ne 15) { throw 'public_layout_crate_count_invalid' }
    if (-not (Test-Path -LiteralPath $EngineFull -PathType Container)) { throw 'engine_root_missing' }
    [void](Resolve-BomberSafePath -Root $EngineFull -Path (Join-Path $EngineFull 'Engine/Build/Build.version') -RequireLeaf)
    [void](Resolve-BomberSafePath -Root $EngineFull -Path (Join-Path $EngineFull 'Engine/Binaries/Win64/UnrealEditor.exe') -RequireLeaf)
    $script:EngineBuildVersion = Get-Content -LiteralPath (Join-Path $EngineFull 'Engine/Build/Build.version') -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
    if ([int]$script:EngineBuildVersion.MajorVersion -ne 5 -or [int]$script:EngineBuildVersion.MinorVersion -ne 7 -or
        [int]$script:EngineBuildVersion.PatchVersion -ne 4 -or [int64]$script:EngineBuildVersion.Changelist -ne [int64]$script:Config.engine.changelist) {
        throw 'engine_identity_mismatch'
    }
    if (Test-Path -LiteralPath $OutputFull) { if (@(Get-ChildItem -LiteralPath $OutputFull -Force).Count -gt 0) { throw 'output_directory_not_empty' } }
    [void](New-Item -ItemType Directory -Path $OutputFull -Force)
    foreach ($name in @('state','captures','receipts','states','logs')) { [void](New-Item -ItemType Directory -Path (Join-Path $OutputFull $name) -Force) }
}
catch {
    $preflightError = $_
}
if ($null -ne $preflightError) {
    try {
        # Respect the output-directory contract even when preflight itself
        # fails: never write an error artifact into a caller-owned non-empty
        # directory.  A fresh/empty directory may receive the structured
        # preflight diagnostic.
        $outputWritable = $false
        if ($OutputFull) {
            $outputWritable = -not (Test-Path -LiteralPath $OutputFull) -or @((Get-ChildItem -LiteralPath $OutputFull -Force -ErrorAction Stop)).Count -eq 0
        }
        if ($outputWritable) {
            if (-not (Test-Path -LiteralPath $OutputFull)) { [void](New-Item -ItemType Directory -Path $OutputFull -Force) }
            $preflight = [ordered]@{schema_version='1.0.0';game_id='Bomber';run_id=$RunId;status='evaluation_not_completed';reason_code='EVALUATOR_PREFLIGHT_FAILED';message='The evaluator could not establish its bound task, engine, or output contract.';diagnostic=([string]$preflightError.Exception.Message -replace '[A-Za-z]:\\[^ ]+','<redacted-path>');candidate_project='<candidate-project>';engine_root='<engine-root>'}
            Write-BomberJson -Value $preflight -Path (Join-Path $OutputFull 'evaluation-not-completed.json')
        }
    } catch { }
    Write-Error ("EVALUATOR_PREFLIGHT_FAILED: " + [string]$preflightError.Exception.Message)
    return
}

$catalog = Get-Content -LiteralPath (Join-Path $EvaluatorRoot 'catalog/checkpoints.json') -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
$script:Verdicts = @(foreach ($checkpoint in $catalog.checkpoints) {
    [pscustomobject][ordered]@{
        checkpoint_id=[string]$checkpoint.id
        dimension=[string]$checkpoint.dimension
        verdict=$null
        detail='Not evaluated.'
        reason_code=$null
        attribution=$null
        first_failure=$null
        score_impact=$null
        evidence=@()
    }
})
$script:VerdictsById = @{}; foreach ($item in $script:Verdicts) { $script:VerdictsById[$item.checkpoint_id] = $item }
$candidateIdentity = Get-ProjectIdentity $ProjectRoot
if ([string]::IsNullOrWhiteSpace($CandidateId)) { $CandidateId = 'candidate-' + $candidateIdentity.Substring(0,16) }
$startedUtc = [DateTime]::UtcNow
$script:Session = $null; $script:SessionActive = $false
$script:GameStatePath = Join-Path $OutputFull 'state/game-state.json'; $engineStatePath = Join-Path $OutputFull 'state/engine-health.json'
$script:ProcessToken = ''; $script:ProcessId = 0
$script:LastAcceptedState = $null
$script:LastStateDiagnostic = $null
$script:StateMaxAgeMs = [double]$script:Config.robustness.state_max_age_ms
$script:StatePollMs = [int]$script:Config.robustness.state_poll_ms
$faults = [Collections.Generic.List[object]]::new()
$warnings = [Collections.Generic.List[object]]::new()
$candidateFailures = [Collections.Generic.List[object]]::new()
$script:CaptureEvidence = [Collections.Generic.List[string]]::new()
$script:CaptureVisualHealth = @{}

try {
    $candidateProjectPresent = Test-Path -LiteralPath $CandidateFull -PathType Leaf
    $descriptor = $null; $descriptorOk = $false
    if ($candidateProjectPresent) {
        try {
            $descriptor = Get-Content -LiteralPath $CandidateFull -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
            $runtimeModuleOk = @($descriptor.Modules | Where-Object { [string]$_.Name -ceq 'BomberStarter' -and [string]$_.Type -in @('Runtime','Developer') }).Count -eq 1
            $blockoutPluginOk = @($descriptor.Plugins | Where-Object { [string]$_.Name -ceq 'BlockoutMap' -and [bool]$_.Enabled }).Count -eq 1
            $descriptorOk = [string]$descriptor.EngineAssociation -ceq '5.7' -and $runtimeModuleOk -and $blockoutPluginOk
        }
        catch { $descriptorOk = $false }
    }
    $assetKitOk = if ($candidateProjectPresent) { Test-CandidateAssetKit } else { $false }
    Set-Checkpoint 'D1-01' $(if ($descriptorOk -and $assetKitOk) {'pass'} else {'fail'}) `
        'The descriptor, runtime module, and exact supplied asset packages were checked.' @('candidate-manifest.json') `
        -ReasonCode $(if (-not $candidateProjectPresent) {'CANDIDATE_PROJECT_MISSING'} elseif (-not $descriptorOk) {'CANDIDATE_DESCRIPTOR_INVALID'} else {'CANDIDATE_ASSET_KIT_INVALID'}) `
        -FirstFailure 'candidate-manifest.json'
    $buildPassed = $false
    $buildMode = 'executed'
    $buildLog = Join-Path $OutputFull 'logs/build.log'
    if ($candidateProjectPresent -and $descriptorOk -and $SkipBuild) {
        $buildMode = 'skipped_with_existing_binary'
        $buildPassed = Test-ExistingBomberBuild
        Write-JsonFile ([ordered]@{
            status = if ($buildPassed) { 'ok' } else { 'failed' }
            mode = $buildMode
            reason_code = if ($buildPassed) { $null } else { 'CANDIDATE_BUILD_ARTIFACT_MISSING' }
            target = 'BomberStarterEditor Win64 Development'
        }) (Join-Path $OutputFull 'receipts/build.json')
    }
    elseif ($candidateProjectPresent -and $descriptorOk) {
        & (Join-Path $EngineFull 'Engine/Build/BatchFiles/Build.bat') BomberStarterEditor Win64 Development $CandidateFull -WaitMutex -NoHotReloadFromIDE *> $buildLog
        $buildPassed = $LASTEXITCODE -eq 0
        Write-JsonFile ([ordered]@{
            status = if ($buildPassed) { 'ok' } else { 'failed' }
            mode = $buildMode
            exit_code = [int]$LASTEXITCODE
            target = 'BomberStarterEditor Win64 Development'
            log = 'logs/build.log'
        }) (Join-Path $OutputFull 'receipts/build.json')
    }
    else {
        Write-JsonFile ([ordered]@{status='not_run';mode='not_run';target='BomberStarterEditor Win64 Development'}) (Join-Path $OutputFull 'receipts/build.json')
    }
    Set-Checkpoint 'D1-02' $(if ($buildPassed) {'pass'} else {'fail'}) 'The Development Editor build target was checked.' `
        @($(if ($SkipBuild) {'receipts/build.json'} elseif (Test-Path -LiteralPath (Join-Path $OutputFull 'logs/build.log')) {'logs/build.log'} else {'receipts/build.json'})) `
        -ReasonCode $(if (-not $candidateProjectPresent) {'CANDIDATE_PROJECT_MISSING'} elseif (-not $descriptorOk) {'CANDIDATE_DESCRIPTOR_INVALID'} else {'CANDIDATE_BUILD_FAILED'}) `
        -FirstFailure $(if (-not $candidateProjectPresent) {$CandidateFull} elseif (-not $descriptorOk) {$CandidateFull} else {'logs/build.log'})
    if (-not $candidateProjectPresent -or -not $descriptorOk -or -not $buildPassed) {
        $staticReason = if (-not $candidateProjectPresent) {'CANDIDATE_PROJECT_MISSING'} elseif (-not $descriptorOk) {'CANDIDATE_DESCRIPTOR_INVALID'} else {'CANDIDATE_BUILD_FAILED'}
        $staticFailure = if ($staticReason -eq 'CANDIDATE_BUILD_FAILED') {'logs/build.log'} else {$CandidateFull}
        Set-Checkpoint 'D1-03' 'fail' 'The invalid or unbuildable candidate could not establish a no-input start.' -ReasonCode $staticReason -FirstFailure $staticFailure
        Set-Checkpoint 'D1-04' 'fail' 'The public game-state provider could not be checked because the candidate did not reach runtime.' -ReasonCode $staticReason -FirstFailure $staticFailure
        Set-Checkpoint 'D1-05' 'fail' 'True Reopen could not be established because the candidate did not reach runtime.' -ReasonCode $staticReason -FirstFailure $staticFailure
        Set-UnresolvedDynamic 'fail' 'Runtime content and player-visible feedback were absent because the candidate did not reach runtime.' @('D2','D5') $staticReason $staticFailure
        Set-UnresolvedDynamic 'unreachable' 'Gameplay rules and lifecycle journeys were unreachable because the candidate did not reach runtime.' @('D3','D4') $staticReason $staticFailure
        $candidateFailures.Add([pscustomobject][ordered]@{reason_code=$staticReason;attribution='candidate';first_failure=$staticFailure;affected_checkpoints=@($script:Verdicts|Where-Object verdict -ne 'pass'|ForEach-Object checkpoint_id);evidence=@($staticFailure)})
        throw 'candidate_static_stop'
    }
    $capturePlugin = & (Join-Path $ScriptRoot 'Build-BomberCapturePlugin.ps1') -EngineRoot $EngineFull
    $runtimeStartedUtc=[DateTime]::UtcNow
    Import-Module (Join-Path $RepositoryRoot 'engine/unreal-5.7.4/executor/UnrealEvaluationExecutor.psm1') -Force
    $start = Start-UnrealEvaluationSession -ProjectPath $CandidateFull -RunRoot $OutputFull -StatePath $engineStatePath -EngineRoot $EngineFull -WindowWidth ([int]$script:Config.robustness.capture_width) -WindowHeight ([int]$script:Config.robustness.capture_height) -TimeoutMs $SessionTimeoutMs -FocusTimeoutMs 2000 -AdditionalArguments @("-EvalGameStatePath=$($script:GameStatePath)", '-ForceRes', "-PLUGIN=$capturePlugin", "-BomberCaptureRoot=$(Join-Path $OutputFull 'captures')")
    [void](Save-Receipt -Value $start -Name 'start')
    if ($start.status -ne 'ok') {
        $startCode = if ($start.fault) { [string]$start.fault.code } else { 'START_FAILED' }
        $startAttribution = Get-StartFaultClassification -Code $startCode -StartResult $start
        if ($startAttribution -eq 'candidate') {
            $reason = if ($startCode -match 'timeout|frame|window') { 'CANDIDATE_START_TIMEOUT' } else { 'CANDIDATE_START_FAILED' }
            Set-Checkpoint 'D1-03' 'fail' 'The built candidate did not publish a usable first runtime frame before the bounded start contract completed.' @('receipts/start.json') $reason 'receipts/start.json'
            Set-Checkpoint 'D1-04' 'fail' 'The candidate runtime provider was unavailable because the candidate did not establish a valid first frame.' @('receipts/start.json') $reason 'receipts/start.json'
            Set-Checkpoint 'D1-05' 'fail' 'True Reopen could not be established because the candidate could not complete its initial launch.' @('receipts/start.json') $reason 'receipts/start.json'
            Set-UnresolvedDynamic 'fail' 'Required runtime content and visible feedback never became available before the candidate start contract completed.' @('D2','D5') $reason 'receipts/start.json'
            Set-UnresolvedDynamic 'unreachable' 'Gameplay rules and lifecycle journeys were unreachable because the candidate could not complete initial launch.' @('D3','D4') $reason 'receipts/start.json'
            $candidateFailures.Add([pscustomobject][ordered]@{reason_code=$reason;attribution='candidate';first_failure='receipts/start.json';affected_checkpoints=@($script:Verdicts|Where-Object verdict -ne 'pass'|ForEach-Object checkpoint_id);evidence=@('receipts/start.json')})
        }
        else {
            $faults.Add([pscustomobject][ordered]@{domain='infrastructure';code=$startCode;message='The evaluator or host could not establish a bound Unreal session.';evidence_paths=@('receipts/start.json');attribution='infrastructure'})
        }
        throw 'session_start_stop'
    }
    $script:Session = $start.result.session; $script:SessionActive = $true; $script:ProcessToken = [string]$start.result.process_token; $script:ProcessId = [int]$start.result.process_id
    $initial = Wait-BomberState -TimeoutSeconds 4 -SaveAs 'initial' -AllowProviderNotReady -Condition { param($state) $true }
    $initialCapture = Save-Capture 'initial'; $startHealthy = $null -ne $initial -and $null -ne $initialCapture
    if ($null -eq $initial) {
        Write-JsonFile ([ordered]@{valid=$false;reason_code='CANDIDATE_STATE_UNAVAILABLE';diagnostic=$script:LastStateDiagnostic}) (Join-Path $OutputFull 'receipts/initial-state-diagnostic.json')
    }
    if ($null -eq $initialCapture) {
        Write-JsonFile ([ordered]@{valid=$false;reason_code='CANDIDATE_CAPTURE_UNAVAILABLE';diagnostic='No valid 1280x720 UE-native render capture was produced.'}) (Join-Path $OutputFull 'receipts/initial-capture-diagnostic.json')
    }
    Set-Checkpoint 'D1-03' $(if ($startHealthy) {'pass'} else {'fail'}) 'The documented entry produced identity-bound envelopes and a 1280x720 frame.' @('states/initial.json','captures/initial.png','receipts/start.json')
    if ($null -eq $initial -or $initial.provider_ready -ne $true) {
        Set-Checkpoint 'D1-04' 'fail' 'The bridge was healthy but no gameplay provider was implemented.' @('states/initial.json') 'CANDIDATE_PROVIDER_MISSING' 'states/initial.json'
        Set-UnresolvedDynamic 'fail' 'The required runtime content or feedback was not implemented.' @('D2','D5') 'CANDIDATE_PROVIDER_MISSING' 'states/initial.json'
        Set-UnresolvedDynamic 'unreachable' 'Gameplay rules and journeys were unreachable because the provider was not implemented.' @('D3','D4') 'CANDIDATE_PROVIDER_MISSING' 'states/initial.json'
        $candidateFailures.Add([pscustomobject][ordered]@{reason_code='CANDIDATE_PROVIDER_MISSING';attribution='candidate';first_failure='states/initial.json';affected_checkpoints=@($script:Verdicts|Where-Object verdict -ne 'pass'|ForEach-Object checkpoint_id);evidence=@('states/initial.json','captures/initial.png')})
        $oldPid = $script:ProcessId; $oldToken = $script:ProcessToken; $script:SessionActive = $false
        $reopen = Reopen-UnrealEvaluationSession -Session $script:Session -GraceTimeoutMs 10000 -StartTimeoutMs 60000; [void](Save-Receipt -Value $reopen -Name 'reopen-starter'); $reopenOk = $false
        if ($reopen.status -eq 'ok') { $script:Session=$reopen.result.session; $script:SessionActive=$true; $script:ProcessId=[int]$reopen.result.process_id; $script:ProcessToken=[string]$reopen.result.process_token; $script:LastAcceptedState=$null; $reopened=Wait-BomberState -TimeoutSeconds 4 -SaveAs 'reopen-starter' -AllowProviderNotReady -Condition {param($state)$true}; $reopenOk=$null-ne$reopened -and $script:ProcessId-ne$oldPid -and $script:ProcessToken-cne$oldToken }
        Set-Checkpoint 'D1-05' $(if ($reopenOk) {'pass'} else {'fail'}) 'True Reopen identity renewal was checked on the starter envelope.' @('receipts/reopen-starter.json','states/reopen-starter.json') -ReasonCode 'CANDIDATE_REOPEN_FAILED' -FirstFailure 'receipts/reopen-starter.json'; throw 'provider_not_ready_stop'
    }
    Set-Checkpoint 'D1-04' 'pass' 'The implemented provider published the complete 2.0.0 game-state shape with stable public object identities.' @('states/initial.json')

    # T01 countdown, exact start, and independent controls. Timing and lock use separate fresh countdowns so injected input cannot truncate a sampled numeral.
    $timingRestart = Invoke-Restart 'countdown-timing-restart'
    $timingStart = Wait-BomberState -TimeoutSeconds 1 -SaveAs 'countdown-timing-start' -Condition {param($s)[string]$s.game_state.feedback.countdown_text-ceq'3'-and[double]$s.game_state.countdown_remaining_ms-ge2600}
    $countdownCapture = Save-Capture 'countdown'
    # Measure countdown bands from the candidate's monotonic state clock rather
    # than from evaluator wall time.  The first stable sample can arrive after
    # the numeral has already been on screen, so seed the interval from the
    # known fresh `3` sample and record transitions only once.
    $sequence=[Collections.Generic.List[string]]::new();$durations=@{};$lastText='';$textStartMonotonic=$null;$watch=[Diagnostics.Stopwatch]::StartNew();$timingActive=$null
    if($timingStart){$sequence.Add('3');$lastText='3';$textStartMonotonic=[double]$timingStart.monotonic_ms}
    while($watch.Elapsed.TotalSeconds-lt 6.0){
        $sample=Read-BomberState
        if($sample){
            $text=[string]$sample.game_state.feedback.countdown_text
            $monotonic=[double]$sample.monotonic_ms
            if($text-in@('3','2','1','GO') -and $text-cne$lastText){
                if($lastText-in@('3','2','1') -and $null-ne$textStartMonotonic){$durations[$lastText]=$monotonic-$textStartMonotonic}
                $sequence.Add($text);$lastText=$text;$textStartMonotonic=$monotonic
            }
            if([string]$sample.game_state.phase-ceq'active'){
                if($lastText-in@('3','2','1') -and $null-ne$textStartMonotonic){$durations[$lastText]=$monotonic-$textStartMonotonic}
                $timingActive=$sample;break
            }
        }
        Start-Sleep -Milliseconds 25
    }
    $lockRestart = Invoke-Restart 'countdown-lock-restart'; [void](Invoke-Press W 'countdown-p1-move'); [void](Invoke-Press Space 'countdown-p1-bomb'); [void](Invoke-Press Up 'countdown-p2-move'); [void](Invoke-Press RightShift 'countdown-p2-bomb')
    $countdownLocked = Wait-BomberState -TimeoutSeconds 1 -SaveAs 'countdown-locked' -Condition {param($s)$p1=Get-Player $s 'player_1';$p2=Get-Player $s 'player_2';[string]$s.game_state.phase-ceq'countdown' -and (Test-Cell $p1.cell $script:ExpectedPlayer1Start.x $script:ExpectedPlayer1Start.y) -and (Test-Cell $p2.cell $script:ExpectedPlayer2Start.x $script:ExpectedPlayer2Start.y) -and @($s.game_state.bombs).Count-eq 0}
    $active=Wait-BomberState -TimeoutSeconds 5 -SaveAs 'active-start' -Condition {param($s)[string]$s.game_state.phase-ceq'active'}
    $countdownOrder=$timingStart-and(($sequence-join',')-ceq'3,2,1,GO');$countdownBands=@(@('3','2','1')|Where-Object{-not$durations.ContainsKey($_)-or[double]$durations[$_]-lt650-or[double]$durations[$_]-gt1350}).Count-eq0;$countdownOk=$timingRestart-and$timingActive-and$lockRestart-and$countdownLocked-and$active-and$countdownOrder-and$countdownBands-and[double]$active.game_state.match_remaining_ms-ge44000
    $actualCrates=@($active.game_state.crates|ForEach-Object{"$($_.cell.x),$($_.cell.y)"}|Sort-Object);$layoutOk=$active-and(Test-CleanRound $active 'active')-and(($script:ExpectedCrateCells-join'|')-ceq($actualCrates-join'|'));$bindingsOk=Test-AssetBindings $active;$arenaCapture=Save-SemanticCapture 'active-arena' 'active-duel' $active {param($s) $s.game_state.phase -eq 'active'};$arenaVisible=$arenaCapture-and(Test-CaptureSceneVisible 'active-arena')
    [void](Invoke-Press A 'p1-border-block');$p1Blocked=Wait-Cell 'player_1' 1 1 'p1-border-block';$p1Move=Press-ToCell D 'player_1' 2 1 'p1-right';$p2Still=if($p1Move){Test-Cell (Get-Player $p1Move 'player_2').cell 9 1}else{$false};[void](Press-ToCell A 'player_1' 1 1 'p1-left')
    [void](Invoke-Press Up 'p2-border-block');$p2Blocked=Wait-Cell 'player_2' 9 1 'p2-border-block';$p2Move=Press-ToCell Left 'player_2' 8 1 'p2-left';$p1Still=if($p2Move){Test-Cell (Get-Player $p2Move 'player_1').cell 1 1}else{$false};[void](Press-ToCell Right 'player_2' 9 1 'p2-right');$movementOk=$p1Blocked-and$p1Move-and$p2Blocked-and$p2Move-and$p2Still-and$p1Still
    Set-Checkpoint 'D2-01' $(if($layoutOk-and$bindingsOk-and$arenaVisible){'pass'}else{'fail'}) 'The exact arena counts, two players, required asset bindings, and a visibly assembled client frame were checked.' @('states/active-start.json','captures/active-arena.png','receipts/capture-active-arena-visual.json') -ReasonCode $(if(-not$arenaVisible){'CANDIDATE_VISUAL_CONTENT_MISSING'}else{'CANDIDATE_REQUIREMENT_FAILED'}) -FirstFailure $(if(-not$arenaVisible){'captures/active-arena.png'}else{'states/active-start.json'});Set-Checkpoint 'D2-02' $(if($countdownOk){'pass'}else{'fail'}) 'The 3, 2, 1, GO countdown and active transition were sampled from a fresh countdown, then input lock was challenged in a separate fresh countdown.' @('states/countdown-timing-start.json','states/countdown-locked.json','states/active-start.json','captures/countdown.png');Set-Checkpoint 'D2-03' $(if($p1Move){'pass'}else{'fail'}) 'Player 1 moved through normal WASD input.' @('states/p1-right.json');Set-Checkpoint 'D2-04' $(if($p2Move-and$p1Still){'pass'}else{'fail'}) 'Player 2 moved independently through normal arrow input.' @('states/p2-left.json')
    Set-Checkpoint 'D3-01' $(if($layoutOk){'pass'}else{'fail'}) 'Start cells, crate cells, walls, resources, and hidden pickups matched the fixed initial state.' @('states/active-start.json');Set-Checkpoint 'D3-02' $(if($countdownOk){'pass'}else{'fail'}) 'All countdown timing bands, input lock, ordering, and one active transition were checked without measurement interference.' @('states/countdown-timing-start.json','states/countdown-locked.json','states/active-start.json');Set-Checkpoint 'D3-03' $(if($movementOk){'pass'}else{'fail'}) 'Both players moved only themselves and respected border blocking.' @('states/p1-border-block.json','states/p1-right.json','states/p2-border-block.json','states/p2-left.json')

    # T02 opening, upgrades, chain, Skate speed, and Player 1 win.
    [void](Invoke-Press Space 'p1-opening-bomb');$armed=Wait-BomberState -TimeoutSeconds 1 -SaveAs 'p1-opening-armed' -Condition {param($s)@($s.game_state.bombs|Where-Object { $_.owner_id -eq 'player_1' }).Count-eq1};$armedBomb=if($armed){@($armed.game_state.bombs|Where-Object { $_.owner_id -eq 'player_1' })[0]}else{$null};$placeEstimate=if($armedBomb){[double]$armed.monotonic_ms+[double]$armedBomb.fuse_remaining_ms-1800.0}else{0.0}
    [void](Invoke-Press Space 'p1-opening-reject');$rejected=Wait-BomberState -TimeoutSeconds 1 -SaveAs 'p1-opening-rejected' -Condition {param($s)@($s.game_state.feedback.messages|Where-Object { $_.text -eq 'BOMB NOT READY' }).Count-gt0-and@($s.game_state.bombs).Count-eq1}
    [void](Press-ToCell S 'player_1' 1 2 'p1-leave-bomb');[void](Invoke-Press W 'p1-reenter-bomb');$bombBlocked=Wait-Cell 'player_1' 1 2 'p1-reenter-bomb';[void](Invoke-Press D 'p1-interior-wall');$wallMoveBlocked=Wait-Cell 'player_1' 1 2 'p1-interior-wall';[void](Press-ToCell S 'player_1' 1 3 'p1-escape-2');[void](Press-ToCell S 'player_1' 1 4 'p1-escape-3')
    $openingBlast=Wait-BomberState -TimeoutSeconds 3 -SaveAs 'p1-opening-blast' -Condition {param($s)@($s.game_state.explosion_cells).Count-gt0};$openingCapture=Save-Capture 'opening-blast';$openingVisible=$openingCapture-and(Test-CaptureSceneVisible 'opening-blast');$fuseObserved=if($openingBlast){[double]$openingBlast.monotonic_ms-$placeEstimate}else{0.0};$blastStart=if($openingBlast){[double]$openingBlast.monotonic_ms}else{0.0};$openingClear=Wait-BomberState -TimeoutSeconds 2 -SaveAs 'p1-opening-clear' -Condition {param($s)@($s.game_state.explosion_cells).Count-eq0-and@($s.game_state.bombs).Count-eq0};$blastObserved=if($openingClear){[double]$openingClear.monotonic_ms-$blastStart}else{0.0}
    $expectedCells=@('1,1','1,2','1,3','2,1','3,1')|Sort-Object;$actualCells=if($openingBlast){@($openingBlast.game_state.explosion_cells|ForEach-Object{"$($_.x),$($_.y)"}|Sort-Object)}else{@()};$shapeOk=($expectedCells-join'|')-ceq($actualCells-join'|');$crateBomb=if($openingBlast){Get-Crate $openingBlast 3 1}else{$null};$bombPower=if($openingBlast){Get-Powerup $openingBlast 'bomb'}else{$null};$openingRuleOk=$shapeOk -and $null -ne $crateBomb -and $null -ne $bombPower -and $crateBomb.state-ceq'destroyed'-and$bombPower.state-ceq'available'
    $baseHold=Measure-HoldToCell W 'player_1' 1 1 'base-hold-up';[void](Press-ToCell D 'player_1' 2 1 'p1-to-bomb-1');$bombCollected=Press-ToCell D 'player_1' 3 1 'p1-collect-bomb'
    [void](Invoke-Press RightShift 'p2-opening-bomb');$p2Armed=Wait-BomberState -TimeoutSeconds 1 -SaveAs 'p2-opening-armed' -Condition {param($s)@($s.game_state.bombs|Where-Object { $_.owner_id -eq 'player_2' }).Count-eq1};Invoke-Sequence @('Down','Down','Down') 'p2-opening-escape';$p2Safe=Wait-Cell 'player_2' 9 4 'p2-opening-safe';$p2Blast=Wait-BomberState -TimeoutSeconds 3 -SaveAs 'p2-opening-blast' -Condition {param($s)@($s.game_state.explosion_cells).Count-gt0};[void](Wait-BomberState -TimeoutSeconds 2 -SaveAs 'p2-opening-clear' -Condition {param($s)@($s.game_state.explosion_cells).Count-eq0-and@($s.game_state.bombs).Count-eq0})
    [void](Invoke-Press Space 'chain-bomb-a');$chainA=Wait-BomberState -TimeoutSeconds 1 -SaveAs 'chain-a-armed' -Condition {param($s)@($s.game_state.bombs).Count-eq1};Invoke-Sequence @('A','A') 'chain-left';[void](Invoke-Press Space 'chain-bomb-b');$chainB=Wait-BomberState -TimeoutSeconds 1 -SaveAs 'chain-b-armed' -Condition {param($s)@($s.game_state.bombs).Count-eq2};Invoke-Sequence @('S','S','S') 'chain-escape'
    $chainExpected=if($chainB){Get-BomberChainExpectation $chainB $publicLayout}else{$null}
    [void](Save-Receipt ([ordered]@{available=($null -ne $chainExpected);expectation=$chainExpected}) 'chain-expectation')
    $chain=Wait-BomberState -TimeoutSeconds 3 -SaveAs 'chain-reaction' -RequiredSamples 1 -Condition {param($s) (Test-BomberChainPresence $s $chainExpected) -and [double]$s.monotonic_ms -lt [double]$chainExpected.later_due_ms}
    $chainCapture=Save-SemanticCapture 'chain-reaction' 'chain-reaction' $chain {param($s) Test-BomberChainPresence $s $chainExpected} $chainExpected
    $chainVisible=$chainCapture -and (Test-CaptureSceneVisible 'chain-reaction')
    $chainClear=Wait-BomberState -TimeoutSeconds 2 -SaveAs 'chain-clear' -Condition {param($s) @($s.game_state.bombs).Count -eq 0 -and @($s.game_state.explosion_cells).Count -eq 0}
    # Pickup availability is observed independently of any chain verdict.
    $revealState=Wait-BomberState -TimeoutSeconds 0.5 -SaveAs 'powerups-revealed' -RequiredSamples 1 -Condition {param($s) Test-BomberPowerupReveal $openingBlast $s}
    $chainContentOk=$null -ne $chain
    $chainTimingOk=$chainContentOk -and [double]$chain.monotonic_ms -lt [double]$chainExpected.later_due_ms
    $chainRefundOk=(Test-BomberChainRefund $chainClear $chainExpected)
    $chainOk=$chainContentOk -and $chainTimingOk -and $chainRefundOk -and (Test-BomberChainSample $chain $chainExpected)
    [void](Save-Receipt ([ordered]@{content=$chainContentOk;triggered_before_later_fuse=$chainTimingOk;single_owner_refunds=$chainRefundOk;expected=$chainExpected;observed_ms=$(if($chain){$chain.monotonic_ms}else{$null})}) 'chain-verification')
    Invoke-Sequence @('W','W','W','D','D','D','D') 'p1-to-fire';$fireCollected=Wait-BomberState -TimeoutSeconds 1 -SaveAs 'fire-collected' -Condition {param($s)[int](Get-Player $s 'player_1').resources.fire-eq3-and(Get-Powerup $s 'fire').state-ceq'collected'};Invoke-Sequence @('A','A','S','S') 'p1-to-skate';$skateCollected=Wait-BomberState -TimeoutSeconds 1 -SaveAs 'skate-collected' -Condition {param($s)[int](Get-Player $s 'player_1').resources.skate-eq1-and(Get-Powerup $s 'skate').state-ceq'collected'};$upgradeCapture=Save-Capture 'all-upgrades';$upgradeVisible=$upgradeCapture-and(Test-CaptureSceneVisible 'all-upgrades')
    Invoke-Sequence @('W','W') 'p1-skate-to-top';$skateHold=Measure-HoldToCell D 'player_1' 9 1 'skate-hold-right';[void](Invoke-Press Space 'p1-winning-bomb');$futureFireBomb=Wait-BomberState -TimeoutSeconds 1 -SaveAs 'fire-three-bomb' -Condition {param($s)@($s.game_state.bombs|Where-Object { $_.owner_id -eq 'player_1' }|Where-Object { $_.captured_fire -eq 3 }).Count-eq1};Invoke-Sequence @('A','A','A','A') 'p1-winning-escape'
    $p1Win=Wait-BomberState -TimeoutSeconds 3 -SaveAs 'player1-win' -Condition {param($s)[string]$s.game_state.phase-ceq'player1_win'-and[string]$s.game_state.feedback.terminal_text-ceq'PLAYER 1 WINS'};$p1WinCapture=Save-SemanticCapture 'player1-win' 'player1-win' $p1Win {param($s) $s.game_state.phase -eq 'player1_win'};$p1WinStable=Wait-BomberState -TimeoutSeconds 2 -SaveAs 'player1-win-stable' -Condition {param($s)[string]$s.game_state.phase-ceq'player1_win'-and@($s.game_state.bombs).Count-eq0-and@($s.game_state.explosion_cells).Count-eq0};$winFingerprint=Get-TerminalFingerprint $p1WinStable;Invoke-Sequence @('W','A','S','D','Space','Left','RightShift') 'p1-win-locked';$winAfter=Read-BomberState;if($winAfter){[void](Save-State $winAfter 'player1-win-after-input')};$winLocked=$winFingerprint-and$winFingerprint-ceq(Get-TerminalFingerprint $winAfter)
    $baseStep=$baseHold.measurement.interval_estimate_ms; $skateStep=$skateHold.measurement.interval_estimate_ms
    $skateTimingOk=$baseHold.state -and $skateHold.state -and $baseHold.measurement.pass -and $skateHold.measurement.pass -and $skateStep -lt $baseStep
    $bombSystemOk=$armed-and$rejected-and$p2Armed-and$bombCollected-and[int](Get-Player $bombCollected 'player_1').resources.bomb_capacity-eq2;$timingOk=$fuseObserved-ge1650-and$fuseObserved-le2000-and$blastObserved-ge300-and$blastObserved-le750;$powerupsOk=$bombCollected-and$fireCollected-and$skateCollected-and@($skateCollected.game_state.powerups|Where-Object { $_.state -eq 'collected' }).Count-eq3
    Set-Checkpoint 'D2-05' $(if($bombSystemOk){'pass'}else{'fail'}) 'Both personal bomb resources and visible bombs were exercised.' @('states/p1-opening-armed.json','states/p2-opening-armed.json');Set-Checkpoint 'D2-06' $(if($openingRuleOk-and$timingOk-and$openingVisible){'pass'}else{'fail'}) 'A timed cross blast destroyed its crate, stopped at walls, and was visibly assembled.' @('states/p1-opening-blast.json','states/p1-opening-clear.json','captures/opening-blast.png','receipts/capture-opening-blast-visual.json') -ReasonCode $(if(-not$openingVisible){'CANDIDATE_VISUAL_CONTENT_MISSING'}else{'CANDIDATE_REQUIREMENT_FAILED'}) -FirstFailure $(if(-not$openingVisible){'captures/opening-blast.png'}else{'states/p1-opening-blast.json'});Set-Checkpoint 'D2-07' $(if($chainContentOk-and$chainVisible){'pass'}else{'fail'}) 'Two armed bombs visibly resolved as one connected chain.' @('states/chain-reaction.json','captures/chain-reaction.png','receipts/capture-chain-reaction-visual.json') -ReasonCode $(if(-not$chainVisible){'CANDIDATE_VISUAL_CONTENT_MISSING'}else{'CANDIDATE_REQUIREMENT_FAILED'}) -FirstFailure $(if(-not$chainVisible){'captures/chain-reaction.png'}else{'states/chain-reaction.json'});Set-Checkpoint 'D2-08' $(if($powerupsOk-and$upgradeVisible){'pass'}else{'fail'}) 'Bomb, Fire, and Skate were revealed, collected, and visibly assembled for Player 1.' @('states/p1-collect-bomb.json','states/fire-collected.json','states/skate-collected.json','captures/all-upgrades.png','receipts/capture-all-upgrades-visual.json') -ReasonCode $(if(-not$upgradeVisible){'CANDIDATE_VISUAL_CONTENT_MISSING'}else{'CANDIDATE_REQUIREMENT_FAILED'}) -FirstFailure $(if(-not$upgradeVisible){'captures/all-upgrades.png'}else{'states/skate-collected.json'});Set-Checkpoint 'D2-09' $(if($p1Win){'pass'}else{'fail'}) 'A Fire 3 blast eliminated Player 2.' @('states/fire-three-bomb.json','states/player1-win.json');Set-Checkpoint 'D2-10' $(if($p1Win){'pass'}else{'fail'}) 'Player 1 win was reached; Player 2 win is checked in T03.' @('states/player1-win.json');Set-Checkpoint 'D2-12' $(if($rejected-and$powerupsOk-and$p1Win-and$upgradeCapture){'pass'}else{'fail'}) 'HUD resources, rejection, pickup messages, and terminal feedback were exercised.' @('states/p1-opening-rejected.json','states/skate-collected.json','states/player1-win.json')
    Set-Checkpoint 'D3-04' $(if($bombSystemOk-and$chainClear){'pass'}else{'fail'}) 'Owner consumption, capacity, refusal, and one refund per bomb were checked.' @('states/p1-opening-armed.json','states/p1-opening-rejected.json','states/chain-clear.json');Set-Checkpoint 'D3-05' $(if($bombBlocked-and$wallMoveBlocked){'pass'}else{'fail'}) 'Player 1 left the bomb cell and was blocked from re-entering it.' @('states/p1-reenter-bomb.json','states/p1-interior-wall.json');Set-Checkpoint 'D3-06' $(if($shapeOk-and$timingOk){'pass'}else{'fail'}) "Observed fuse=$([math]::Round($fuseObserved))ms and blast=$([math]::Round($blastObserved))ms with the exact Fire 2 cross." @('states/p1-opening-blast.json','states/p1-opening-clear.json');Set-Checkpoint 'D3-07' $(if($shapeOk-and$actualCells-notcontains'0,1'-and$actualCells-notcontains'1,0'){'pass'}else{'fail'}) 'Border walls remained excluded and stopped the blast.' @('states/p1-opening-blast.json');Set-Checkpoint 'D3-08' $(if($openingRuleOk-and$openingClear){'pass'}else{'fail'}) 'The Bomb crate was destroyed once, stopped its ray, and its cell became traversable.' @('states/p1-opening-blast.json','states/p1-collect-bomb.json');Set-Checkpoint 'D3-09' $(if($revealState){'pass'}else{'fail'}) 'Designated pickups were checked independently after their revealing blasts.' @('states/p1-opening-blast.json','states/powerups-revealed.json','states/powerups-revealed-samples.json');Set-Checkpoint 'D3-10' $(if($bombCollected-and[int](Get-Player $bombCollected 'player_1').resources.bombs_available-eq2){'pass'}else{'fail'}) 'Bomb collection changed only Player 1 to 2/2.' @('states/p1-collect-bomb.json');Set-Checkpoint 'D3-11' $(if($chainA-and[int]$chainA.game_state.bombs[0].captured_fire-eq2-and$futureFireBomb){'pass'}else{'fail'}) 'Pre-pickup bombs retained Fire 2 and a later bomb captured Fire 3.' @('states/chain-a-armed.json','states/fire-collected.json','states/fire-three-bomb.json');Set-Checkpoint 'D3-12' $(if($skateTimingOk){'pass'}else{'fail'}) "Snapshot-bounded repeated movement: base=$baseStep ms; Skate=$skateStep ms. See measurement receipts for uncertainty bounds." @('states/base-hold-up-samples.json','states/skate-hold-right-samples.json','receipts/base-hold-up-measurement.json','receipts/skate-hold-right-measurement.json');Set-Checkpoint 'D3-13' $(if($chainOk){'pass'}else{'fail'}) 'The two-bomb connected chain resolved once with both owner refunds and each captured range.' @('receipts/chain-verification.json','states/chain-reaction-samples.json','states/chain-clear.json');Set-Checkpoint 'D3-14' $(if($p1Win-and(Get-Player $p1Win 'player_1').alive-eq$true-and(Get-Player $p1Win 'player_2').alive-eq$false){'pass'}else{'fail'}) 'The direct transaction committed the correct surviving player winner.' @('states/player1-win.json');Set-Checkpoint 'D4-01' $(if($openingRuleOk-and$powerupsOk-and$chainContentOk-and$p1Win){'pass'}else{'fail'}) 'One normal-input journey opened lanes, collected all upgrades, chained bombs, and reached Player 1 win.' @('states/p1-opening-blast.json','states/chain-reaction.json','states/skate-collected.json','states/player1-win.json');Set-Checkpoint 'D5-04' $(if($openingVisible-and$chainVisible-and$upgradeVisible-and$rejected){'pass'}else{'fail'}) 'Bomb refusal, cross/chain explosion, crate, and pickup transitions have contemporaneous visibly assembled captures.' @('captures/opening-blast.png','captures/chain-reaction.png','captures/all-upgrades.png','receipts/capture-opening-blast-visual.json','receipts/capture-chain-reaction-visual.json','receipts/capture-all-upgrades-visual.json') -ReasonCode $(if(-not($openingVisible-and$chainVisible-and$upgradeVisible)){'CANDIDATE_VISUAL_CONTENT_MISSING'}else{'CANDIDATE_REQUIREMENT_FAILED'}) -FirstFailure $(if(-not$openingVisible){'captures/opening-blast.png'}elseif(-not$chainVisible){'captures/chain-reaction.png'}else{'captures/all-upgrades.png'})

    # T03 Player 2 win and countdown restart.
    $restartA=Invoke-Restart 'restart-after-p1-win';Start-Sleep -Milliseconds 250;$restartB=Invoke-Restart 'restart-during-countdown';Start-Sleep -Milliseconds 900;$staleCountdown=Read-BomberState;if($staleCountdown){[void](Save-State $staleCountdown 'countdown-restart-stable')};$restartCountdownOk=$restartA-and$restartB-and$staleCountdown-and[string]$staleCountdown.game_state.phase-ceq'countdown'-and(Test-CleanRound $staleCountdown);$round2Active=Wait-BomberState -TimeoutSeconds 5 -SaveAs 'player2-win-active' -Condition {param($s)[string]$s.game_state.phase-ceq'active'}
    [void](Invoke-Press Space 'p1-self-bomb');$p2Win=Wait-BomberState -TimeoutSeconds 3 -SaveAs 'player2-win' -Condition {param($s)[string]$s.game_state.phase-ceq'player2_win'-and[string]$s.game_state.feedback.terminal_text-ceq'PLAYER 2 WINS'};$p2WinCapture=Save-Capture 'player2-win';$p2Stable=Wait-BomberState -TimeoutSeconds 2 -SaveAs 'player2-win-stable' -Condition {param($s)[string]$s.game_state.phase-ceq'player2_win'-and@($s.game_state.bombs).Count-eq0-and@($s.game_state.explosion_cells).Count-eq0};$p2Fingerprint=Get-TerminalFingerprint $p2Stable;Invoke-Sequence @('Up','Left','RightShift','W','Space') 'p2-win-locked';$p2After=Read-BomberState;if($p2After){[void](Save-State $p2After 'player2-win-after-input')};$p2Locked=$p2Fingerprint-and$p2Fingerprint-ceq(Get-TerminalFingerprint $p2After)
    Set-Checkpoint 'D2-10' $(if($p1Win-and$p2Win){'pass'}else{'fail'}) 'Both exact winner outcomes were reached through normal play.' @('states/player1-win.json','states/player2-win.json');Set-Checkpoint 'D4-02' $(if($p2Win-and$p2Locked){'pass'}else{'fail'}) 'A clean self-bomb journey reached and locked Player 2 win.' @('states/player2-win.json','states/player2-win-after-input.json')

    # T04 simultaneous-death draw.
    [void](Invoke-Restart 'restart-before-draw');[void](Wait-BomberState -TimeoutSeconds 5 -SaveAs 'draw-active' -Condition {param($s)[string]$s.game_state.phase-ceq'active'})
    [void](Invoke-Press Space 'draw-open-p1');Invoke-Sequence @('S','S','S') 'draw-open-p1-escape';[void](Wait-BomberState -TimeoutSeconds 3 -SaveAs 'draw-open-p1-blast' -Condition {param($s)@($s.game_state.explosion_cells).Count-gt0});[void](Wait-BomberState -TimeoutSeconds 2 -SaveAs 'draw-open-p1-clear' -Condition {param($s)@($s.game_state.bombs).Count-eq0-and@($s.game_state.explosion_cells).Count-eq0})
    [void](Invoke-Press RightShift 'draw-open-p2');Invoke-Sequence @('Down','Down','Down') 'draw-open-p2-escape';[void](Wait-BomberState -TimeoutSeconds 3 -SaveAs 'draw-open-p2-blast' -Condition {param($s)@($s.game_state.explosion_cells).Count-gt0});[void](Wait-BomberState -TimeoutSeconds 2 -SaveAs 'draw-open-p2-clear' -Condition {param($s)@($s.game_state.bombs).Count-eq0-and@($s.game_state.explosion_cells).Count-eq0})
    Invoke-Sequence @('W','W','W','D','D') 'draw-p1-bomb-up';[void](Wait-BomberState -TimeoutSeconds 1 -SaveAs 'draw-bomb-collected' -Condition {param($s)[int](Get-Player $s 'player_1').resources.bomb_capacity-eq2});[void](Invoke-Press Space 'draw-corridor-a');Invoke-Sequence @('A','A') 'draw-corridor-left';[void](Invoke-Press Space 'draw-corridor-b');Invoke-Sequence @('S','S','S') 'draw-corridor-escape';[void](Wait-BomberState -TimeoutSeconds 3 -SaveAs 'draw-corridor-chain' -Condition {param($s)@($s.game_state.explosion_cells).Count-ge7});[void](Wait-BomberState -TimeoutSeconds 2 -SaveAs 'draw-corridor-clear' -Condition {param($s)@($s.game_state.bombs).Count-eq0-and@($s.game_state.explosion_cells).Count-eq0})
    Invoke-Sequence @('Up','Up','Up','Left','Left','Left','Left','Left','Left','Left') 'draw-p2-position';$p2Position=Wait-Cell 'player_2' 2 1 'draw-p2-at-2-1';Invoke-Sequence @('W','W','W','D','D') 'draw-p1-to-3-1';[void](Invoke-Press Space 'draw-final-a');Invoke-Sequence @('A','A') 'draw-final-left';[void](Invoke-Press Space 'draw-final-b');[void](Press-ToCell S 'player_1' 1 2 'draw-p1-at-1-2')
    $simDraw=Wait-BomberState -TimeoutSeconds 3 -SaveAs 'simultaneous-draw' -Condition {param($s)[string]$s.game_state.phase-ceq'draw'-and-not(Get-Player $s 'player_1').alive-and-not(Get-Player $s 'player_2').alive};$simDrawCapture=Save-Capture 'simultaneous-draw'

    # T05 restart cancellation and Reopen are completed before the long no-input timeout window.
    # This preserves the public semantics while preventing a late host focus event from erasing
    # already measured lifecycle evidence.
    $restartFromTerminal=Invoke-Restart 'restart-after-simultaneous-draw';[void](Wait-BomberState -TimeoutSeconds 5 -SaveAs 'post-draw-active' -Condition {param($s)[string]$s.game_state.phase-ceq'active'});[void](Invoke-Press Space 'pre-restart-armed-bomb');$preRestartBomb=Wait-BomberState -TimeoutSeconds 1 -SaveAs 'pre-restart-armed-bomb' -Condition {param($s)@($s.game_state.bombs).Count-eq1};$staleRestart=Invoke-Restart 'restart-cancel-armed-bomb';Start-Sleep -Milliseconds 2200;$afterStaleDeadline=Read-BomberState;if($afterStaleDeadline){[void](Save-State $afterStaleDeadline 'after-stale-bomb-deadline')};$staleCancelled=$staleRestart-and$afterStaleDeadline-and[string]$afterStaleDeadline.game_state.phase-ceq'countdown'-and@($afterStaleDeadline.game_state.bombs).Count-eq0-and@($afterStaleDeadline.game_state.explosion_cells).Count-eq0-and@($afterStaleDeadline.game_state.crates|Where-Object { $_.state -eq 'present' }).Count-eq15;$restartOk=$restartCountdownOk-and$restartFromTerminal-and$staleCancelled;Set-Checkpoint 'D4-04' $(if($restartOk){'pass'}else{'fail'}) 'Countdown, terminal, and armed-bomb restarts created clean identities and canceled stale work.' @('states/countdown-restart-stable.json','states/restart-after-simultaneous-draw-state.json','states/after-stale-bomb-deadline.json')
    [void](Wait-BomberState -TimeoutSeconds 5 -SaveAs 'pre-reopen-active' -Condition {param($s)[string]$s.game_state.phase-ceq'active'});[void](Invoke-Press D 'pre-reopen-progress');$preReopenProgress=Read-BomberState;if($preReopenProgress){[void](Save-State $preReopenProgress 'pre-reopen-progress')}
    $oldPid=$script:ProcessId;$oldToken=$script:ProcessToken;$script:SessionActive=$false;$reopen=Reopen-UnrealEvaluationSession -Session $script:Session -GraceTimeoutMs 10000 -StartTimeoutMs 60000;[void](Save-Receipt $reopen 'reopen');$reopenOk=$false;$reopened=$null
    if($reopen.status-eq'ok'){$script:Session=$reopen.result.session;$script:SessionActive=$true;$script:ProcessId=[int]$reopen.result.process_id;$script:ProcessToken=[string]$reopen.result.process_token;$script:LastAcceptedState=$null;$reopened=Wait-BomberState -TimeoutSeconds 5 -SaveAs 'reopened' -RequiredSamples 2 -Condition {param($s)[string]$s.game_state.phase-ceq'countdown'};$reopenCapture=Save-Capture 'reopened';$reopenOk=$reopened-and$script:ProcessId-ne$oldPid-and$script:ProcessToken-cne$oldToken-and[int]$reopened.round_index-eq0-and[int]$reopened.restart_count-eq0-and(Test-CleanRound $reopened)}
    Set-Checkpoint 'D1-05' $(if($reopenOk){'pass'}else{'fail'}) 'True Reopen renewed process identity and returned to a fresh countdown.' @('receipts/reopen.json','states/reopened.json','captures/reopened.png') -ReasonCode 'CANDIDATE_REOPEN_FAILED' -FirstFailure 'receipts/reopen.json';Set-Checkpoint 'D4-05' $(if($preReopenProgress-and$reopenOk){'pass'}else{'fail'}) 'True Reopen discarded the progressed round and reset process-local indices.' @('states/pre-reopen-progress.json','states/reopened.json') -ReasonCode 'CANDIDATE_REOPEN_FAILED' -FirstFailure 'receipts/reopen.json'
    [void](Wait-BomberState -TimeoutSeconds 5 -SaveAs 'timeout-active' -Condition {param($s)[string]$s.game_state.phase-ceq'active'});$urgency=Wait-BomberState -TimeoutSeconds 38 -SaveAs 'timeout-urgency' -Condition {param($s)[string]$s.game_state.phase-ceq'active'-and$s.game_state.feedback.urgency_active-eq$true-and[double]$s.game_state.match_remaining_ms-le10000};$urgencyCapture=Save-Capture 'timeout-urgency';$timeoutDraw=Wait-BomberState -TimeoutSeconds 12 -SaveAs 'timeout-draw' -Condition {param($s)[string]$s.game_state.phase-ceq'draw'-and[double]$s.game_state.match_remaining_ms-eq0-and(Get-Player $s 'player_1').alive-and(Get-Player $s 'player_2').alive};$timeoutCapture=Save-Capture 'timeout-draw'
    $drawsOk=$simDraw-and$timeoutDraw;$terminalLocksOk=$winLocked-and$p2Locked;Set-Checkpoint 'D2-11' $(if($drawsOk){'pass'}else{'fail'}) 'Both simultaneous-death and timeout draws were reached.' @('states/simultaneous-draw.json','states/timeout-draw.json');Set-Checkpoint 'D3-15' $(if($drawsOk-and$terminalLocksOk){'pass'}else{'fail'}) 'Both draw rules and winner terminal locks were checked.' @('states/simultaneous-draw.json','states/timeout-draw.json','states/player1-win-after-input.json','states/player2-win-after-input.json');Set-Checkpoint 'D4-03' $(if($drawsOk){'pass'}else{'fail'}) 'Clean normal-input journeys reached simultaneous-death and timeout DRAW.' @('states/simultaneous-draw.json','states/timeout-draw.json')
    $allCaptures=$arenaCapture-and$openingCapture-and$chainCapture-and$upgradeCapture-and$p1WinCapture-and$p2WinCapture-and$simDrawCapture-and$timeoutCapture
    Set-Checkpoint 'D5-01' $(if($active.game_state.feedback.hud.visible-and@($active.game_state.feedback.hud.players).Count-eq2-and$arenaCapture){'pass'}else{'fail'}) 'Time, Alive, and both player resource panels were captured with synchronized state.' @('states/active-start.json','captures/active-arena.png');Set-Checkpoint 'D5-02' $(if($countdownCapture-and$urgency-and$urgencyCapture){'pass'}else{'fail'}) 'Countdown and final-ten-second urgency were captured with matching state.' @('captures/countdown.png','states/timeout-urgency.json','captures/timeout-urgency.png');Set-Checkpoint 'D5-03' $(if($bindingsOk-and$movementOk-and$arenaVisible){'pass'}else{'fail'}) 'Both supplied character/material roles, Player 1 marker, controls, and movement were checked in a visibly assembled arena.' @('states/active-start.json','captures/active-arena.png','receipts/capture-active-arena-visual.json') -ReasonCode $(if(-not$arenaVisible){'CANDIDATE_VISUAL_CONTENT_MISSING'}else{'CANDIDATE_REQUIREMENT_FAILED'}) -FirstFailure $(if(-not$arenaVisible){'captures/active-arena.png'}else{'states/active-start.json'});Set-Checkpoint 'D5-05' $(if($p1WinCapture-and$p2WinCapture-and$simDrawCapture-and$timeoutCapture-and$terminalLocksOk){'pass'}else{'fail'}) 'All exact terminal overlays were captured and the winner states remained locked.' @('captures/player1-win.png','captures/player2-win.png','captures/simultaneous-draw.png','captures/timeout-draw.png');Set-Checkpoint 'D5-06' $(if($assetKitOk-and$bindingsOk-and$arenaVisible-and$chainVisible-and$upgradeVisible){'pass'}else{'fail'}) 'All mandatory supplied model roles were bound and visible in representative 1280x720 frames.' @('captures/active-arena.png','captures/chain-reaction.png','captures/all-upgrades.png','receipts/capture-active-arena-visual.json','receipts/capture-chain-reaction-visual.json','receipts/capture-all-upgrades-visual.json') -ReasonCode $(if(-not($arenaVisible-and$chainVisible-and$upgradeVisible)){'CANDIDATE_VISUAL_CONTENT_MISSING'}else{'CANDIDATE_REQUIREMENT_FAILED'}) -FirstFailure $(if(-not$arenaVisible){'captures/active-arena.png'}elseif(-not$chainVisible){'captures/chain-reaction.png'}else{'captures/all-upgrades.png'})
}
catch {
    $message = [string]$_.Exception.Message
    if ($message -notin @('candidate_static_stop','session_start_stop','provider_not_ready_stop')) {
        [void](Save-Receipt ([ordered]@{message=$message;exception_type=$_.Exception.GetType().FullName;script_stack=$_.ScriptStackTrace}) 'runtime-exception')
        # Unexpected runtime failures are candidate defects by default. Only
        # explicitly identified evaluator/host faults invalidate a run; this
        # prevents a candidate crash or malformed state from becoming N/A.
        $infra = $message -match '(?i)^(measurement_fault:|evaluator_|engine_|host_|executor_|environment_|unsupported_|input_(lease|watchdog|cleanup)|capture_visual_measurement_fault:.*(System\.Drawing|assembly)|cleanup_)' -or
            $_.Exception -is [System.Management.Automation.ParameterBindingException] -or
            $message -match '(?i)(null-valued expression|property .* cannot be found|Unable to find type)'
        if ($infra) {
            $faults.Add([pscustomobject][ordered]@{domain='infrastructure';code='runtime_exception';message='The evaluator or host raised an identified infrastructure fault.';diagnostic=$message;evidence_paths=@('receipts/runtime-exception.json')})
        }
        else {
            # A candidate may stop after a valid first frame but before the
            # explicit True Reopen checkpoint is reached.  Close that
            # checkpoint as a candidate failure so the run remains scoreable
            # instead of tripping the evaluator's unresolved-contract fault.
            if (@($script:Verdicts | Where-Object { $_.checkpoint_id -eq 'D1-05' -and $null -eq $_.verdict }).Count -gt 0) {
                Set-Checkpoint 'D1-05' 'fail' `
                    'True Reopen was not demonstrated before the candidate runtime stopped.' `
                    @('runtime') 'CANDIDATE_RUNTIME_FAILURE' 'runtime'
            }
            $candidateFailures.Add([pscustomobject][ordered]@{reason_code='CANDIDATE_RUNTIME_FAILURE';attribution='candidate';first_failure='runtime';diagnostic=$message;affected_checkpoints=@($script:Verdicts | Where-Object { $null -eq $_.verdict } | ForEach-Object checkpoint_id);evidence=@()})
            Set-UnresolvedDynamic 'fail' 'The candidate runtime stopped before this content or feedback checkpoint was demonstrated.' @('D2','D5') 'CANDIDATE_RUNTIME_FAILURE' 'runtime'
            Set-UnresolvedDynamic 'unreachable' 'The candidate runtime stopped before this rule or lifecycle checkpoint was reachable.' @('D3','D4') 'CANDIDATE_RUNTIME_FAILURE' 'runtime'
        }
    }
}
finally {
    if ($script:SessionActive -and $null -ne $script:Session) {
        try {
            $stop=Stop-UnrealEvaluationSession -Session $script:Session -GraceTimeoutMs 10000 -FaultCleanupTimeoutMs 5000
            [void](Save-Receipt $stop 'stop')
            $cleanupVerified = $stop.result -and $stop.result.process_exited -eq $true -and $stop.result.input_lease_released -eq $true -and $stop.result.input_cleanup.all_released -eq $true
            if (-not $cleanupVerified) {
                $faults.Add([pscustomobject][ordered]@{domain='cleanup';code='cleanup_not_verified';message='Final process or input cleanup was not verified.';evidence_paths=@('receipts/stop.json')})
            }
            elseif ($stop.status -ne 'ok') {
                $warnings.Add([pscustomobject][ordered]@{domain='cleanup';code=[string]$stop.fault.code;message='Normal close required bounded forced cleanup, but the process tree and controlled input were fully released.';evidence_paths=@('receipts/stop.json')})
            }
        }
        catch {$faults.Add([pscustomobject][ordered]@{domain='cleanup';code='cleanup_exception';message='Final cleanup raised an exception.';diagnostic=$_.Exception.Message;evidence_paths=@()})}
    }
    if ($faults.Count -eq 0) {
        $unresolved = @($script:Verdicts | Where-Object { $null -eq $_.verdict })
        if ($unresolved.Count -gt 0) {
            $faults.Add([pscustomobject][ordered]@{domain='evaluator';code='unresolved_checkpoint_contract';message='A completed evaluator path left checkpoints unresolved.';affected_checkpoints=@($unresolved|ForEach-Object checkpoint_id);evidence_paths=@()})
        }
    }
    foreach ($failure in @($script:Verdicts | Where-Object { $_.verdict -in @('fail','unreachable') })) {
        if (@($candidateFailures | Where-Object { $_.affected_checkpoints -contains $failure.checkpoint_id }).Count -eq 0) {
            $candidateFailures.Add([pscustomobject][ordered]@{reason_code=[string]$failure.reason_code;attribution='candidate';first_failure=[string]$failure.first_failure;affected_checkpoints=@([string]$failure.checkpoint_id);evidence=@($failure.evidence)})
        }
    }
    $elapsedSeconds = if (Get-Variable runtimeStartedUtc -ErrorAction SilentlyContinue) { ([DateTime]::UtcNow - $runtimeStartedUtc).TotalSeconds } else { 0.0 }
    if ($elapsedSeconds -gt [double]$script:Config.robustness.session_watchdog_seconds) {
        $faults.Add([pscustomobject][ordered]@{domain='infrastructure';code='session_watchdog_exceeded';message='The bounded evaluator session exceeded its watchdog budget.';elapsed_seconds=[Math]::Round($elapsedSeconds,3);watchdog_seconds=[int]$script:Config.robustness.session_watchdog_seconds;evidence_paths=@()})
    }
    $runStatus = if ($faults.Count -eq 0) {'completed'} else {'run_invalid'}
    $manifest=[ordered]@{schema_version='3.0.0';game_id=[string]$script:Config.game_id;task_name=[string]$publicManifest.task_name;task_revision=[string]$script:Config.task_revision;candidate_id=$CandidateId;candidate_project_name=[IO.Path]::GetFileName($CandidateFull);candidate_project_path=Get-BomberRelativePath -Root $OutputFull -Path $CandidateFull;candidate_identity_sha256=$candidateIdentity;engine="Unreal Engine $($script:Config.engine.version)";engine_changelist=[int64]$script:Config.engine.changelist;runtime_mode=[string]$script:Config.engine.runtime_mode;viewport=[ordered]@{width=[int]$script:Config.robustness.capture_width;height=[int]$script:Config.robustness.capture_height;dpi_scale=1.0};public_binding=[ordered]@{release_revision=[string]$publicManifest.release_revision;gdd_sha256=$script:PublicBinding.gdd_sha256;layout_sha256=$script:PublicBinding.layout_sha256}};Write-JsonFile $manifest (Join-Path $OutputFull 'candidate-manifest.json')
    $record=[ordered]@{schema_version='3.0.0';game_id=[string]$script:Config.game_id;task_name=[string]$publicManifest.task_name;task_revision=[string]$script:Config.task_revision;run_id=$RunId;candidate_id=$CandidateId;candidate_identity_sha256=$candidateIdentity;evaluator_revision=[string]$script:Config.evaluator_revision;engine="Unreal Engine $($script:Config.engine.version)";engine_changelist=[int64]$script:Config.engine.changelist;runtime_mode=[string]$script:Config.engine.runtime_mode;started_utc=$startedUtc.ToString('o');finished_utc=[DateTime]::UtcNow.ToString('o');run_status=$runStatus;diagnostic_only=$true;formal_freeze_performed=$false;checkpoints=$script:Verdicts;candidate_failures=@($candidateFailures);faults=@($faults);warnings=@($warnings);captures=@($script:CaptureEvidence);budget=[ordered]@{declared_serial_worst_case_seconds=240;session_watchdog_seconds=[int]$script:Config.robustness.session_watchdog_seconds;headroom_seconds=120;timeout_draw_seconds=50;conditional_waits_seconds=105;stable_samples=$script:StableSamples;state_poll_ms=$script:StatePollMs}};$verdictsPath=Join-Path $OutputFull 'verdicts.json';Write-JsonFile $record $verdictsPath
    if ($runStatus -eq 'completed' -and (-not $DiagnosticsOnly -or $D6RunPath)) {
        & (Join-Path $ScriptRoot 'Complete-BomberEvaluation.ps1') -RunDirectory $OutputFull -Model $VlmModel -BaseUrl $VlmBaseUrl -TimeoutSeconds $VlmTimeoutSeconds -D6RunPath $D6RunPath
    }
    elseif ($runStatus -eq 'completed') {
        Write-JsonFile ([ordered]@{schema_version='1.0.0';game_id=[string]$script:Config.game_id;run_id=$RunId;status='evaluation_not_completed';reason_code='D6_EVIDENCE_REQUIRED_FOR_SCORE';message='D1-D5 diagnostics completed, but no compliant three-round D6 evidence was supplied; no score row was published.';verdicts='verdicts.json'}) (Join-Path $OutputFull 'evaluation-not-completed.json')
    }
    elseif ($runStatus -eq 'run_invalid') {
        Write-JsonFile ([ordered]@{schema_version='1.0.0';game_id='Bomber';run_id=$RunId;status='evaluation_not_completed';faults=@($faults)}) (Join-Path $OutputFull 'evaluation-not-completed.json')
    }
    Write-Output $verdictsPath
}
