Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/ActionRoguelikeAtomicChecks.ps1')
function O($Value){@{value=$Value;trust='verified'}}
function Assert($Ok,$Message){if(-not$Ok){throw $Message}}
$before=@{identity=@{monotonic_ms=100};player=@{entity_id=(O 'player');credits=(O 0);health=(O 50);teleport_acquired=(O $false)};objects=@(@{entity_id=(O 'item');object_type=(O 'credits_pickup');available=(O $true)})}
$after=$before|ConvertTo-Json -Depth 20|ConvertFrom-Json -AsHashtable -Depth 20
$after.identity.monotonic_ms=200;$after.player.credits.value=40;$after.objects[0].available.value=$false
$event=@{event_type='pickup';monotonic_ms=150;subject=$null;object=$null;payload=@{resource='credits';value_before=0;value_after=40;amount=40}}
$context=@{before=$before;states=@($before,$after);trace=@{setup=@{target_entity_id='item'}};events=@($event)}
$raw=$event|ConvertTo-Json -Depth 20 -Compress
Assert (@(Get-AREvents $context 'pickup' 'credits_pickup' 'item').Count-eq1) 'Unique item transition was rejected.'
Assert (@(Get-AREvents $context 'pickup' 'player' 'player').Count-eq1) 'Exact player delta was rejected.'
Assert (@(Get-AREvents $context 'projectile_spawned' 'player_projectile').Count-eq0) 'A process event was invented.'
Assert (@(Get-AREvents $context 'pickup' 'credits_pickup' 'other').Count-eq0) 'Wrong item accepted.'
Assert (($event|ConvertTo-Json -Depth 20 -Compress)-ceq$raw) 'Published event changed.'
$event.payload.value_after=80
Assert (@(Get-AREvents $context 'pickup' 'credits_pickup' 'item').Count-eq0) 'Contradictory amount accepted.'
$event.payload.value_after=40;$event.subject=@{role='player';entity_id='wrong-player'}
Assert (@(Get-AREvents $context 'pickup' 'player' 'player').Count-eq0) 'Explicit foreign identity overwritten.'
$event.subject=$null;$after.objects[0].available.value=$true
Assert (@(Get-AREvents $context 'pickup' 'credits_pickup' 'item').Count-eq0) 'Uncorroborated item consumption accepted.'
$after.objects[0].available.value=$false
Write-Output 'ACTIONROGUELIKE_SPARSE_REFERENCES_OK null_roles=true exact_state_delta=true explicit_conflict_rejected=true raw_unchanged=true'
$states=@(foreach($time in @(100,200,300)){
    @{identity=@{monotonic_ms=$time};player=@{health=(O $(if($time-eq300){0}else{1}))};processes=@();enemies=@(@{entity_id=(O 'enemy');ai_mode=(O 'melee');action_state=(O $(if($time-eq300){'idle'}else{'melee_attack'}))})}
})
$damage=@{subject=$null;object=$null;monotonic_ms=250;payload=@{value_before=1;value_after=0}}
$melee=@{states=$states}
Assert (Test-ARObservedMeleeSettlement $melee $damage) 'Unique observed melee settlement rejected.'
$states[1].enemies[0].action_state.value='idle'
Assert (-not(Test-ARObservedMeleeSettlement $melee $damage)) 'Missing continuous attack accepted.'
$states[1].enemies[0].action_state.value='melee_attack';$damage.object=@{role='physics_prop';entity_id='wrong-source'}
Assert (-not(Test-ARObservedMeleeSettlement $melee $damage)) 'Explicit contradictory source replaced.'
Write-Output 'ACTIONROGUELIKE_OBSERVED_MELEE_OK continuous_attack=true exact_health_settlement=true foreign_source_rejected=true'
