[CmdletBinding()]
param([Parameter(Mandatory)][string]$Path)
$ErrorActionPreference = 'Stop'
$schema = Join-Path (Split-Path $PSScriptRoot) 'contracts/game-state.schema.json'
$text = Get-Content -LiteralPath $Path -Raw -Encoding utf8
if (-not (Test-Json -Json $text -SchemaFile $schema -ErrorAction Stop)) { throw 'Observation schema validation failed.' }
$sample = $text | ConvertFrom-Json -Depth 50
if ($sample.provider_ready) {
    $state = $sample.game_state
    if (@($state.ordinary_cells).Count -ne $state.ordinary_remaining) { throw 'Ordinary count disagrees with actual cell list.' }
    if (@($state.energizer_cells).Count -ne $state.energizers_remaining) { throw 'Energizer count disagrees with actual cell list.' }
    foreach ($field in @('ordinary_cells','energizer_cells')) {
        $names = @($state.$field | ForEach-Object { '{0},{1}' -f $_.x,$_.y })
        if (@($names | Select-Object -Unique).Count -ne $names.Count) { throw "Duplicate cell in $field." }
    }
    if ($null -ne $state.run_id) {
        if (@($state.ghosts).Count -ne 4 -or @($state.ghosts.id | Select-Object -Unique).Count -ne 4) { throw 'A run requires four distinct semantic ghost IDs.' }
        if ($state.ordinary_consumed + $state.ordinary_remaining -ne 299) { throw 'Ordinary-dot conservation mismatch.' }
    }
    foreach ($target in $state.targets) {
        if ($target.visible -and $null -eq $target.rect) { throw 'Visible target has no client rectangle.' }
        if ($target.rect -and (($target.rect.x + $target.rect.width) -gt 1.00001 -or ($target.rect.y + $target.rect.height) -gt 1.00001)) { throw 'Target rectangle extends beyond the client.' }
    }
}
[ordered]@{ status='passed'; schema_version='1.0.0'; gameplay_verified=$false } | ConvertTo-Json
