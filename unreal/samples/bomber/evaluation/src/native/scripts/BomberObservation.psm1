Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-BomberCellKey($Cell) { return "$([int]$Cell.x),$([int]$Cell.y)" }

function Get-BomberChainExpectation {
    param([Parameter(Mandatory)]$Before, [Parameter(Mandatory)]$Layout)
    # Public grid and pre-action facts only. No candidate object/class lookup.
    $bombs = @($Before.game_state.bombs | Where-Object state -eq 'armed' | Sort-Object { [double]$_.fuse_remaining_ms })
    if ($bombs.Count -lt 2) { return $null }
    $byCell = @{}; foreach ($b in $bombs) { $byCell[(Get-BomberCellKey $b.cell)] = $b }
    $crates = @{}; foreach ($c in $Before.game_state.crates | Where-Object state -eq 'present') { $crates[(Get-BomberCellKey $c.cell)] = $true }
    $queue = [Collections.Generic.Queue[object]]::new(); $queue.Enqueue($bombs[0])
    $resolved = @{}; $cells = @{}
    while ($queue.Count) {
        $bomb = $queue.Dequeue()
        if ($resolved.ContainsKey([string]$bomb.object_id)) { continue }
        $resolved[[string]$bomb.object_id] = $bomb
        $cells[(Get-BomberCellKey $bomb.cell)] = $true
        foreach ($d in @(@(1,0),@(-1,0),@(0,1),@(0,-1))) {
            for ($i=1; $i -le [int]$bomb.captured_fire; ++$i) {
                $x=[int]$bomb.cell.x+$d[0]*$i; $y=[int]$bomb.cell.y+$d[1]*$i
                if ($y -lt 0 -or $y -ge $Layout.rows.Count -or $x -lt 0 -or $x -ge $Layout.rows[$y].Length -or $Layout.rows[$y][$x] -eq '#') { break }
                $key="$x,$y"; $cells[$key]=$true
                if ($byCell.ContainsKey($key)) { $queue.Enqueue($byCell[$key]); break }
                if ($crates.ContainsKey($key)) { break }
            }
        }
    }
    if ($resolved.Count -lt 2) { return $null }
    $refunds=@{}; foreach($p in $Before.game_state.players) { $refunds[[string]$p.object_id]=[int]$p.resources.bombs_available }
    foreach($b in $resolved.Values) { $refunds[[string]$b.owner_id]++ }
    return [pscustomobject]@{
        process_token=$Before.process_token; round_id=$Before.round_id
        bombs=@($resolved.Values | Sort-Object object_id); cells=@($cells.Keys | Sort-Object)
        due_ms=[double]$Before.monotonic_ms+[double]$bombs[0].fuse_remaining_ms
        later_due_ms=[double]$Before.monotonic_ms+[double]$bombs[1].fuse_remaining_ms
        refunds=$refunds
    }
}

function Test-BomberChainPresence {
    param($State, $Expected)
    if ($null -eq $State -or $null -eq $Expected) { return $false }
    if ($State.process_token -cne $Expected.process_token -or $State.round_id -cne $Expected.round_id) { return $false }
    $actual=@($State.game_state.explosion_cells | ForEach-Object { Get-BomberCellKey $_ } | Sort-Object -Unique)
    foreach ($b in $Expected.bombs) {
        if ((Get-BomberCellKey $b.cell) -notin $actual) { return $false }
    }
    # Both retained exploding records and removed resolved records are legal.
    foreach ($b in $Expected.bombs) {
        if (@($State.game_state.bombs | Where-Object { $_.object_id -ceq $b.object_id -and $_.state -eq 'armed' }).Count) { return $false }
    }
    return $true
}

function Test-BomberChainSample {
    param($State, $Expected)
    if (-not (Test-BomberChainPresence $State $Expected)) { return $false }
    $actual=@($State.game_state.explosion_cells | ForEach-Object { Get-BomberCellKey $_ } | Sort-Object -Unique)
    return ($actual -join '|') -ceq ($Expected.cells -join '|')
}

function Test-BomberChainRefund {
    param($State, $Expected)
    if ($null -eq $State -or $null -eq $Expected -or $State.round_id -cne $Expected.round_id -or $State.process_token -cne $Expected.process_token) { return $false }
    foreach ($p in $State.game_state.players) {
        if ([int]$p.resources.bombs_available -ne $Expected.refunds[[string]$p.object_id]) { return $false }
    }
    return $true
}

function Test-BomberPowerupReveal {
    param($Opening, $Later)
    if ($null -eq $Opening -or $null -eq $Later -or $Opening.round_id -cne $Later.round_id -or $Opening.process_token -cne $Later.process_token) { return $false }
    $required=@{bomb='3,1';fire='5,1';skate='3,3'}
    if (@($Later.game_state.powerups).Count -ne 3) { return $false }
    foreach($kind in $required.Keys) {
        $source=if($kind -eq 'bomb'){$Opening}else{$Later}
        $pickup=@($source.game_state.powerups | Where-Object kind -eq $kind)
        if($pickup.Count -ne 1 -or $pickup[0].state -cne 'available' -or -not $pickup[0].visible -or (Get-BomberCellKey $pickup[0].cell) -cne $required[$kind]) { return $false }
        $crate=@($source.game_state.crates | Where-Object { (Get-BomberCellKey $_.cell) -ceq $required[$kind] })
        if($crate.Count -ne 1 -or $crate[0].state -cne 'destroyed') { return $false }
    }
    return $true
}

function Measure-BomberMovementSamples {
    param([object[]]$Samples, [string]$PlayerId, [double]$MinimumMs, [double]$MaximumMs)
    $transitions=[Collections.Generic.List[object]]::new(); $previous=$null
    foreach($s in $Samples) {
        $p=@($s.game_state.players | Where-Object object_id -eq $PlayerId)[0]
        if($null -ne $previous) {
            if($s.process_token -cne $previous.state.process_token -or $s.round_id -cne $previous.state.round_id -or [double]$s.monotonic_ms -le [double]$previous.state.monotonic_ms) { throw 'measurement_fault:movement_identity_or_clock' }
            $distance=[Math]::Abs([int]$p.cell.x-[int]$previous.cell.x)+[Math]::Abs([int]$p.cell.y-[int]$previous.cell.y)
            if($distance -gt 0) {
                $transitions.Add([pscustomobject]@{cell=$p.cell;lower_ms=[double]$previous.state.monotonic_ms;upper_ms=[double]$s.monotonic_ms})
            }
        }
        $previous=[pscustomobject]@{state=$s;cell=$p.cell}
    }
    $result=[ordered]@{status='unreachable';pass=$false;interval_lower_ms=$null;interval_upper_ms=$null;interval_estimate_ms=$null;repeat_count=0;transitions=@($transitions);sample_count=$Samples.Count}
    if($transitions.Count -lt 2) { return [pscustomobject]$result }
    $first=$transitions[0]; $last=$transitions[$transitions.Count-1]
    $count=[Math]::Abs([int]$last.cell.x-[int]$first.cell.x)+[Math]::Abs([int]$last.cell.y-[int]$first.cell.y)
    if($count -lt 2) { return [pscustomobject]$result }
    $lower=($last.lower_ms-$first.upper_ms)/$count; $upper=($last.upper_ms-$first.lower_ms)/$count
    $result.repeat_count=$count; $result.interval_lower_ms=$lower; $result.interval_upper_ms=$upper; $result.interval_estimate_ms=($lower+$upper)/2
    # Broad transport uncertainty is an evaluator limitation, not a slow player.
    if($upper-$lower -gt 60) { $result.status='measurement_invalid' }
    else { $result.status='measured'; $result.pass=($upper -ge $MinimumMs -and $lower -le $MaximumMs) }
    return [pscustomobject]$result
}

function Merge-BomberMovementMeasurements {
    param([object[]]$Measurements, [double]$MinimumMs, [double]$MaximumMs)
    $lower = ($Measurements.interval_lower_ms | Measure-Object -Maximum).Maximum
    $upper = ($Measurements.interval_upper_ms | Measure-Object -Minimum).Minimum
    $status = if ($lower -gt $upper -or $upper-$lower -gt 60) { 'measurement_invalid' } else { 'measured' }
    return [pscustomobject]@{
        status=$status;pass=($status -eq 'measured' -and $upper -ge $MinimumMs -and $lower -le $MaximumMs)
        interval_lower_ms=$lower;interval_upper_ms=$upper;interval_estimate_ms=($lower+$upper)/2
        method='intersection_of_all_same_tier_corridor_brackets';trials=@($Measurements)
    }
}

function Assert-BomberSemanticCapture {
    param([string]$CapturePath, [string]$StateId, [string]$CandidateIdentity)
    if(-not (Test-Path -LiteralPath $CapturePath -PathType Leaf)) { return }
    $sidecar=[IO.Path]::ChangeExtension($CapturePath,'.semantic.json')
    if(-not (Test-Path -LiteralPath $sidecar -PathType Leaf)) { throw "D6_SEMANTIC_EVIDENCE_MISSING:$StateId" }
    $proof=Get-Content -LiteralPath $sidecar -Raw | ConvertFrom-Json -Depth 100
    if($proof.status -cne 'bound' -or $proof.state_id -cne $StateId -or $proof.candidate_identity_sha256 -cne $CandidateIdentity -or $proof.capture_sha256 -cne (Get-FileHash -LiteralPath $CapturePath -Algorithm SHA256).Hash.ToLowerInvariant()) { throw "D6_SEMANTIC_BINDING_INVALID:$StateId" }
    if($proof.before.process_token -cne $proof.after.process_token -or $proof.before.round_id -cne $proof.after.round_id -or [double]$proof.after.monotonic_ms -lt [double]$proof.before.monotonic_ms) { throw "D6_SEMANTIC_IDENTITY_INVALID:$StateId" }
    $native=$proof.native_capture
    if($native.producer -cne 'ue-native-viewport' -or $native.status -cne 'ok' -or $native.process_token -cne $proof.before.process_token -or $native.width -ne 1280 -or $native.height -ne 720 -or [double]$native.monotonic_ms -lt [double]$proof.before.monotonic_ms -or [double]$native.monotonic_ms -gt [double]$proof.after.monotonic_ms) { throw "D6_NATIVE_CAPTURE_BINDING_INVALID:$StateId" }
    foreach($state in @($proof.before,$proof.after)) {
        switch($StateId) {
            'active-duel' { if($state.game_state.phase -cne 'active') { throw 'D6_SEMANTIC_PHASE_INVALID:active-duel' } }
            'chain-reaction' { if(-not (Test-BomberChainPresence $state $proof.chain_expectation)) { throw 'D6_SEMANTIC_PHASE_INVALID:chain-reaction' } }
            'player1-win' { if($state.game_state.phase -cne 'player1_win') { throw 'D6_SEMANTIC_PHASE_INVALID:player1-win' } }
        }
    }
}

Export-ModuleMember -Function Get-BomberChainExpectation,Test-BomberChainPresence,Test-BomberChainSample,Test-BomberChainRefund,Test-BomberPowerupReveal,Measure-BomberMovementSamples,Merge-BomberMovementMeasurements,Assert-BomberSemanticCapture
