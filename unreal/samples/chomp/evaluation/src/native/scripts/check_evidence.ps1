param([Parameter(Mandatory)][string]$Run)
$ErrorActionPreference='Stop'
$chompTask=Split-Path (Split-Path $PSScriptRoot)
$schema=Join-Path $chompTask 'input/contracts/game-state.schema.json'
$count=0
foreach($capture in Get-ChildItem -LiteralPath (Join-Path $Run 'session/captures') -Filter '*.json') {
    $record=Get-Content -LiteralPath $capture.FullName -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100
    foreach($side in @('before','after')) {
        $s=$record.$side
        if(!$s){continue}
        $json=$s | ConvertTo-Json -Depth 100 -Compress
        if(!(Test-Json -Json $json -SchemaFile $schema -ErrorAction Stop)){throw "Schema mismatch: $($capture.Name) $side"}
        if($s.provider_ready){
            $g=$s.game_state
            if(@($g.ordinary_cells).Count -ne $g.ordinary_remaining -or @($g.energizer_cells).Count -ne $g.energizers_remaining){throw 'Pickup population mismatch.'}
            if($g.run_id -and $g.ordinary_remaining+$g.ordinary_consumed -ne 299){throw 'Ordinary conservation mismatch.'}
        }
        $count++
    }
}
@{status='passed';validated_capture_snapshots=$count;method='Public JSON Schema and population invariants on every capture boundary'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Run 'evidence-schema-check.json') -Encoding utf8
Get-Content -LiteralPath (Join-Path $Run 'evidence-schema-check.json')
