Set-StrictMode -Version Latest

function ConvertTo-BomberCanonicalJson {
    param([Parameter(Mandatory)]$Value)
    return (($Value | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n")
}

function Write-BomberJson {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Path
    )
    $parent = Split-Path -Parent $Path
    if ($parent) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    [IO.File]::WriteAllText($Path, (ConvertTo-BomberCanonicalJson $Value), [Text.UTF8Encoding]::new($false))
}

function Get-BomberSha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-BomberTextSha256 {
    param([Parameter(Mandatory)][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($Text)))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-BomberEvaluatorConfig {
    param([Parameter(Mandatory)][string]$EvaluatorRoot)
    $path = Join-Path $EvaluatorRoot 'contracts/evaluator-config.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'evaluator_config_missing' }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 50
}

function Get-BomberPublicBinding {
    param([Parameter(Mandatory)][string]$TaskRoot)
    $manifestPath = Join-Path $TaskRoot 'input/BENCHMARK_MANIFEST.json'

    $gddPath = Join-Path $TaskRoot 'input/GDD.md'
    $layoutPath = Join-Path $TaskRoot 'input/project/Config/BomberArenaLayout.json'
    $stateSchemaPath = Join-Path $TaskRoot 'input/contracts/game-state.schema.json'
    foreach ($path in @($manifestPath, $gddPath, $layoutPath, $stateSchemaPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "public_binding_missing:$path" }
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 50
    $gddHash = Get-BomberSha256 $gddPath
    $gddArtifact = @($manifest.artifacts | Where-Object { [string]$_.path -ceq 'GDD.md' }) | Select-Object -First 1
    if ($null -eq $gddArtifact -or [string]$gddArtifact.sha256 -cne $gddHash) { throw 'public_gdd_hash_mismatch' }
    [pscustomobject][ordered]@{
        manifest = $manifest
        manifest_path = $manifestPath

        gdd_path = $gddPath
        layout_path = $layoutPath
        state_schema_path = $stateSchemaPath
        manifest_sha256 = Get-BomberSha256 $manifestPath

        gdd_sha256 = $gddHash
        layout_sha256 = Get-BomberSha256 $layoutPath
        state_schema_sha256 = Get-BomberSha256 $stateSchemaPath
    }
}

function Resolve-BomberSafePath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path,
        [switch]$RequireLeaf,
        [switch]$RequireContainer
    )
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $candidate = [IO.Path]::GetFullPath($Path)
    $prefix = $rootFull + [IO.Path]::DirectorySeparatorChar
    if ($candidate -ine $rootFull -and -not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'path_outside_root'
    }
    if (Test-Path -LiteralPath $candidate) {
        $item = Get-Item -LiteralPath $candidate -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'reparse_point_not_allowed' }
        if ($RequireLeaf -and $item.PSIsContainer) { throw 'expected_file' }
        if ($RequireContainer -and -not $item.PSIsContainer) { throw 'expected_directory' }
    }
    return $candidate
}

function Get-BomberProjectIdentity {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
        return Get-BomberTextSha256 "missing-project-root:$ProjectRoot"
    }
    $excluded = '[\\/](Binaries|DerivedDataCache|Intermediate|Saved|\.vs|\.idea|evaluation|\.scratch)[\\/]'
    $lines = foreach ($file in Get-ChildItem -LiteralPath $ProjectRoot -File -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch $excluded } | Sort-Object FullName) {
        $relative = [IO.Path]::GetRelativePath($ProjectRoot, $file.FullName).Replace('\','/')
        "$relative`t$(Get-BomberSha256 $file.FullName)`t$([int64]$file.Length)"
    }
    return Get-BomberTextSha256 ($lines -join "`n")
}

function Test-BomberCell {
    param($Cell, [int]$X, [int]$Y)
    return $null -ne $Cell -and [int]$Cell.x -eq $X -and [int]$Cell.y -eq $Y
}

function Test-BomberStateEnvelope {
    param(
        $State,
        [Parameter(Mandatory)][string]$ExpectedProcessToken,
        [Parameter(Mandatory)][int]$ExpectedProcessId,
        [switch]$AllowProviderNotReady,
        [object]$PreviousState
    )
    if ($null -eq $State) { return [pscustomobject][ordered]@{ valid = $false; code = 'STATE_MISSING' } }
    foreach ($name in @('schema_version','process_token','process_id','snapshot_id','round_id','round_index','restart_count','monotonic_ms','bridge_ready','provider_ready','game_state')) {
        if ($State.PSObject.Properties.Name -notcontains $name) { return [pscustomobject][ordered]@{ valid=$false;code='STATE_FIELD_MISSING';field=$name } }
    }
    if ([string]$State.schema_version -cne '2.0.0') { return [pscustomobject][ordered]@{valid=$false;code='STATE_SCHEMA_VERSION'} }
    if ([string]$State.process_token -cne $ExpectedProcessToken -or [int]$State.process_id -ne $ExpectedProcessId) {
        return [pscustomobject][ordered]@{valid=$false;code='STATE_IDENTITY_MISMATCH'}
    }
    if ($State.bridge_ready -ne $true) { return [pscustomobject][ordered]@{valid=$false;code='STATE_BRIDGE_NOT_READY'} }
    if ($null -ne $PreviousState) {
        # Polling may be faster than the public 250 ms heartbeat. A repeated
        # sample is neither new evidence nor a contradictory observation.
        if ([int64]$State.snapshot_id -eq [int64]$PreviousState.snapshot_id -and
            [double]$State.monotonic_ms -eq [double]$PreviousState.monotonic_ms) {
            return [pscustomobject][ordered]@{valid=$false;code='STATE_SNAPSHOT_REPEATED'}
        }
        if ([int64]$State.snapshot_id -le [int64]$PreviousState.snapshot_id -or [double]$State.monotonic_ms -lt [double]$PreviousState.monotonic_ms) {
            return [pscustomobject][ordered]@{valid=$false;code='STATE_NOT_ADVANCING'}
        }
    }
    if ($State.provider_ready -ne $true) {
        if ($AllowProviderNotReady -and $null -eq $State.game_state) { return [pscustomobject][ordered]@{valid=$true;provider_ready=$false} }
        return [pscustomobject][ordered]@{valid=$false;code='STATE_PROVIDER_NOT_READY'}
    }
    $game = $State.game_state
    if ($null -eq $game -or [string]$game.phase -notin @('countdown','active','player1_win','player2_win','draw')) {
        return [pscustomobject][ordered]@{valid=$false;code='STATE_GAME_SHAPE'}
    }
    foreach ($name in @('countdown_remaining_ms','match_remaining_ms','players','bombs','explosion_cells','crates','powerups','feedback','asset_bindings')) {
        if ($game.PSObject.Properties.Name -notcontains $name) { return [pscustomobject][ordered]@{valid=$false;code='STATE_GAME_FIELD_MISSING';field=$name} }
    }
    if ([double]$game.countdown_remaining_ms -lt 0 -or [double]$game.countdown_remaining_ms -gt 3000 -or
        [double]$game.match_remaining_ms -lt 0 -or [double]$game.match_remaining_ms -gt 45000) { return [pscustomobject][ordered]@{valid=$false;code='STATE_TIME_RANGE'} }
    if (@($game.players).Count -ne 2 -or @($game.crates).Count -ne 15 -or @($game.powerups).Count -ne 3 -or @($game.bombs).Count -gt 4) { return [pscustomobject][ordered]@{valid=$false;code='STATE_COLLECTION_CARDINALITY'} }
    $players = @($game.players | Sort-Object slot)
    if ([string]$players[0].object_id -cne 'player_1' -or [string]$players[1].object_id -cne 'player_2' -or [int]$players[0].slot -ne 1 -or [int]$players[1].slot -ne 2) { return [pscustomobject][ordered]@{valid=$false;code='STATE_PLAYER_IDENTITY'} }
    foreach ($player in $players) {
        if ($null -eq $player.cell -or $null -eq $player.resources) { return [pscustomobject][ordered]@{valid=$false;code='STATE_PLAYER_SHAPE'} }
        if ([int]$player.resources.bombs_available -gt [int]$player.resources.bomb_capacity) { return [pscustomobject][ordered]@{valid=$false;code='STATE_RESOURCE_INVARIANT'} }
        if ([bool]$player.alive -and [string]$player.movement_state -eq 'dead') { return [pscustomobject][ordered]@{valid=$false;code='STATE_MOVEMENT_INVARIANT'} }
    }
    $ids = @($game.bombs | ForEach-Object { [string]$_.object_id })
    if (@($ids | Sort-Object -Unique).Count -ne $ids.Count) { return [pscustomobject][ordered]@{valid=$false;code='STATE_DUPLICATE_BOMB_ID'} }
    $crateIds = @($game.crates | ForEach-Object { [string]$_.object_id })
    if (@($crateIds | Sort-Object -Unique).Count -ne $crateIds.Count) { return [pscustomobject][ordered]@{valid=$false;code='STATE_DUPLICATE_CRATE_ID'} }
    $powerIds = @($game.powerups | ForEach-Object { [string]$_.object_id })
    if (@($powerIds | Sort-Object -Unique).Count -ne $powerIds.Count) { return [pscustomobject][ordered]@{valid=$false;code='STATE_DUPLICATE_POWERUP_ID'} }
    $hud = $game.feedback.hud
    if ($null -eq $hud -or @($hud.players).Count -ne 2 -or [int]$hud.alive_count -ne @($players | Where-Object alive -eq $true).Count) { return [pscustomobject][ordered]@{valid=$false;code='STATE_HUD_INCONSISTENT'} }
    $expectedTerminal = switch ([string]$game.phase) {
        'player1_win' { 'PLAYER 1 WINS' }
        'player2_win' { 'PLAYER 2 WINS' }
        'draw' { 'DRAW' }
        default { '' }
    }
    if ([string]$game.feedback.terminal_text -cne $expectedTerminal) { return [pscustomobject][ordered]@{valid=$false;code='STATE_TERMINAL_TEXT'} }
    return [pscustomobject][ordered]@{valid=$true;provider_ready=$true}
}

function Get-BomberRelativePath {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Path)
    return [IO.Path]::GetRelativePath([IO.Path]::GetFullPath($Root), [IO.Path]::GetFullPath($Path)).Replace('\','/')
}

Export-ModuleMember -Function @(
    'ConvertTo-BomberCanonicalJson','Write-BomberJson','Get-BomberSha256','Get-BomberTextSha256',
    'Get-BomberEvaluatorConfig','Get-BomberPublicBinding','Resolve-BomberSafePath','Get-BomberProjectIdentity',
    'Test-BomberCell','Test-BomberStateEnvelope','Get-BomberRelativePath'
)
