Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/ActionRoguelikeAtomicChecks.ps1')
function Assert($Ok,$Message){if(-not$Ok){throw $Message}}
$raw=@{player=@{position_m=@{value=@{x=1200.0;y=-350.0;z=122.0};trust='verified'};facing=@{value=@{x=1.;y=0.;z=0.};trust='verified'}}}
$bytes=$raw|ConvertTo-Json -Depth 10 -Compress
$script:ARMetricBinding=$null
Assert ((Get-ARValue $raw 'player.position_m').x-eq1200) 'Default meters changed.'
$script:ARMetricBinding=@{scale_to_meters=.01}
Assert ((Get-ARValue $raw 'player.position_m').x-eq12) 'Centimeters were not converted.'
Assert ((Get-ARValue $raw 'player.position_m').x-eq12) 'Repeated reads applied the scale twice.'
Assert ((Get-ARValue $raw 'player.facing').x-eq1) 'Unitless facing was scaled.'
Assert (($raw|ConvertTo-Json -Depth 10 -Compress)-ceq$bytes) 'Raw evidence was mutated.'
Assert-ARMetricCorroboration $raw @{native_player_position_m=@{x=12.;y=-3.5;z=1.22}}
$rejected=$false
try{Assert-ARMetricCorroboration $raw @{native_player_position_m=@{x=1200.;y=-350.;z=122.}}}catch{$rejected=$_.Exception.Message-like'run_invalid|METRIC_ADAPTER_UNCORROBORATED|*'}
Assert $rejected 'An uncorroborated unit interpretation was accepted.'
$script:ARMetricBinding=$null
Write-Output 'ACTIONROGUELIKE_METRIC_ADAPTER_OK raw_unchanged=true native_corroboration=true'
