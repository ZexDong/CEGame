function New-BomberTestFixture([string]$EvaluatorRoot) {
    # Synthetic test data only; never used for a candidate or a published score.
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('bomber-unit-'+[guid]::NewGuid().ToString('N'))
    $root=Join-Path $temp 'unreal/Bomber/evaluator'
    [void](New-Item -ItemType Directory -Path $root -Force)
    foreach($dir in @('scripts','contracts','catalog','schemas')){Copy-Item -LiteralPath (Join-Path $EvaluatorRoot $dir) -Destination $root -Recurse}
    $d6=Join-Path $root 'd6';[void](New-Item -ItemType Directory -Path (Join-Path $d6 'reference') -Force)
    foreach($name in @('d6-reference-manifest.json','protocol.json','model-binding.json','FIXED_VLM_PROMPT.txt')){Copy-Item -LiteralPath (Join-Path $EvaluatorRoot "d6/$name") -Destination $d6}
    [void](New-Item -ItemType Directory -Path (Join-Path $temp 'gamecreate'))
    Copy-Item -LiteralPath (Join-Path $EvaluatorRoot '../../../gamecreate/GAME_INDEPENDENT_SCORING_GUIDE.md') -Destination (Join-Path $temp 'gamecreate')
    Add-Type -AssemblyName System.Drawing.Common
    $manifest=Get-Content -LiteralPath (Join-Path $d6 'd6-reference-manifest.json') -Raw|ConvertFrom-Json
    foreach($state in $manifest.states){
        $path=Join-Path $d6 $state.reference_image
        $bitmap=[Drawing.Bitmap]::new(1280,720);$g=[Drawing.Graphics]::FromImage($bitmap)
        try{$g.Clear([Drawing.Color]::Navy);$g.FillRectangle([Drawing.Brushes]::Orange,320,100,600,500);$bitmap.Save($path,[Drawing.Imaging.ImageFormat]::Png)}finally{$g.Dispose();$bitmap.Dispose()}
        $state.sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $manifest.status='ready';$manifest.source_identity_sha256='f'*64;$manifest.reason='Synthetic unit fixture, not a game reference.'
    $manifest|ConvertTo-Json -Depth 100|Set-Content -LiteralPath (Join-Path $d6 'd6-reference-manifest.json') -Encoding utf8
    $protocol=Get-Content -LiteralPath (Join-Path $d6 'protocol.json') -Raw|ConvertFrom-Json
    $protocol.reference_manifest_sha256=(Get-FileHash -LiteralPath (Join-Path $d6 'd6-reference-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    $protocol|ConvertTo-Json -Depth 100|Set-Content -LiteralPath (Join-Path $d6 'protocol.json') -Encoding utf8
    return [pscustomobject]@{temp=$temp;root=$root}
}
function Remove-BomberTestFixture([string]$Path){
    $full=[IO.Path]::GetFullPath($Path);$prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\bomber-unit-'
    if(-not $full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe test cleanup path.'}
    if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}
