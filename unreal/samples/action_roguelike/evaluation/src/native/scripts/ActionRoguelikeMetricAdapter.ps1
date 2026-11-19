Set-StrictMode -Version Latest

# Explicit source-audited units only. Raw publisher snapshots, event batches,
# identities and hashes remain unchanged; callers receive a derived vector.
function Convert-ARMetricValue($Value,[string]$Path) {
    $binding=Get-Variable ARMetricBinding -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if($null-eq$Value-or$null-eq$binding-or$Path-notmatch'(^|\.)(position_m|target_position_m|velocity_mps)$'){return $Value}
    $converted=[ordered]@{}
    foreach($axis in @('x','y','z')){
        $n=if($Value-is[Collections.IDictionary]){$Value[$axis]}else{$Value.$axis}
        $converted[$axis]=[double]$n*[double]$binding.scale_to_meters
    }
    return $converted
}

function Assert-ARMetricCorroboration($Snapshot,$Reply) {
    $binding=Get-Variable ARMetricBinding -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if($null-eq$binding){return}
    $raw=$Snapshot.player.position_m.value
    $metric=Convert-ARMetricValue $raw 'position_m'
    $native=$Reply.native_player_position_m
    if($Snapshot.player.position_m.trust-cne'verified'-or$null-eq$native){throw 'run_invalid|METRIC_ADAPTER_UNCORROBORATED|Missing independent player position.'}
    $distance=0.0
    foreach($axis in @('x','y','z')){$distance+=[Math]::Pow($metric[$axis]-[double]$native.$axis,2)}
    if([Math]::Sqrt($distance)-gt0.25){throw 'run_invalid|METRIC_ADAPTER_UNCORROBORATED|Source-audited units disagree with native world coordinates.'}
}
