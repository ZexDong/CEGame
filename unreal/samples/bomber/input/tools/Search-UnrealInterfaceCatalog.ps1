[CmdletBinding()]
param(
    [string]$Name,
    [string]$Kind,
    [string]$Owner,
    [ValidateRange(1,1000)][int]$Limit = 50,
    [string]$CatalogPath = (Join-Path $PSScriptRoot '../tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.jsonl.gz'),
    [string]$IndexPath = (Join-Path $PSScriptRoot '../tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.index.json')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$catalogFull = (Resolve-Path -LiteralPath $CatalogPath).Path
$index = Get-Content -LiteralPath (Resolve-Path -LiteralPath $IndexPath).Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 16
$dictionary = $index.value_dictionary
$file = [IO.File]::Open($catalogFull, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
$gzip = [IO.Compression.GZipStream]::new($file, [IO.Compression.CompressionMode]::Decompress, $false)
$reader = [IO.StreamReader]::new($gzip, [Text.UTF8Encoding]::new($false), $true, 65536, $false)
try {
    $count = 0
    while (-not $reader.EndOfStream -and $count -lt $Limit) {
        $line = $reader.ReadLine()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $entry = $line | ConvertFrom-Json -Depth 16
        if ($Name -and [string]$entry.name -notlike "*$Name*") { continue }
        if ($Kind -and [string]$entry.kind -cne $Kind) { continue }
        if ($Owner -and [string]$entry.owner -notlike "*$Owner*") { continue }
        foreach ($field in @('preconditions','return_or_result','faults','side_effects','validation','limitations')) {
            $code = [string]$entry.$field
            if ($null -ne $dictionary.PSObject.Properties[$code]) { $entry.$field = [string]$dictionary.$code }
        }
        foreach ($parameter in @($entry.parameters)) {
            $code = [string]$parameter.units_or_range
            if ($null -ne $dictionary.PSObject.Properties[$code]) { $parameter.units_or_range = [string]$dictionary.$code }
        }
        $entry
        $count += 1
    }
}
finally {
    $reader.Dispose()
    $gzip.Dispose()
    $file.Dispose()
}

