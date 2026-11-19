# Run with Windows PowerShell 5.1 for built-in WinRT projection; no cloud OCR.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ImagePath,[string]$OutputPath)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null=[Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]
$null=[Windows.Storage.Streams.IRandomAccessStream,Windows.Storage.Streams,ContentType=WindowsRuntime]
$null=[Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics.Imaging,ContentType=WindowsRuntime]
$null=[Windows.Graphics.Imaging.SoftwareBitmap,Windows.Graphics.Imaging,ContentType=WindowsRuntime]
$null=[Windows.Graphics.Imaging.BitmapTransform,Windows.Graphics.Imaging,ContentType=WindowsRuntime]
$null=[Windows.Graphics.Imaging.BitmapBounds,Windows.Graphics.Imaging,ContentType=WindowsRuntime]
$null=[Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime]
$null=[Windows.Media.Ocr.OcrResult,Windows.Foundation,ContentType=WindowsRuntime]
$null=[Windows.Globalization.Language,Windows.Globalization,ContentType=WindowsRuntime]
$async=([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetGenericArguments().Count -eq 1 -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1)
function Await($operation,[Type]$type) {
    $task=$async.MakeGenericMethod($type).Invoke($null,@($operation))
    if(-not $task.Wait(20000)){throw 'OCR operation timed out'}
    $task.GetAwaiter().GetResult()
}
$file=Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync([IO.Path]::GetFullPath($ImagePath))) ([Windows.Storage.StorageFile])
$stream=Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$bitmap=$null
try {
    $decoder=Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $bitmap=Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $language=[Windows.Globalization.Language]::new('en-US')
    $engine=[Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($language)
    if($null -eq $engine){$engine=[Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()}
    if($null -eq $engine){throw 'No installed OCR engine is available'}
    # Busy game artwork can make whole-frame OCR discard an otherwise readable
    # HUD. Always run the same geometric bands; no expected score/value is used.
    $width=$bitmap.PixelWidth;$height=$bitmap.PixelHeight
    $regions=@(@{y=0;height=$height;full=$true})
    $edges=@(0,.16,.32,.84,1)
    for($i=0;$i -lt $edges.Count-1;$i++){
        $top=[int][Math]::Floor($edges[$i]*$height);$bottom=[int][Math]::Floor($edges[$i+1]*$height)
        $regions+=@{y=$top;height=$bottom-$top;full=$false}
    }
    $lines=[Collections.Generic.List[object]]::new();$seen=[Collections.Generic.HashSet[string]]::new()
    foreach($region in $regions){
        $sample=$bitmap
        try{
            if(-not $region.full){
                $bounds=[Windows.Graphics.Imaging.BitmapBounds]::new()
                $bounds.X=0;$bounds.Y=[uint32]$region.y;$bounds.Width=[uint32]$width;$bounds.Height=[uint32]$region.height
                $transform=[Windows.Graphics.Imaging.BitmapTransform]::new();$transform.Bounds=$bounds
                $sample=Await ($decoder.GetSoftwareBitmapAsync([Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8,[Windows.Graphics.Imaging.BitmapAlphaMode]::Premultiplied,$transform,[Windows.Graphics.Imaging.ExifOrientationMode]::IgnoreExifOrientation,[Windows.Graphics.Imaging.ColorManagementMode]::DoNotColorManage)) ([Windows.Graphics.Imaging.SoftwareBitmap])
            }
            $result=Await ($engine.RecognizeAsync($sample)) ([Windows.Media.Ocr.OcrResult])
            foreach($line in $result.Lines){
                $words=@($line.Words | ForEach-Object {[ordered]@{text=$_.Text;x=$_.BoundingRect.X;y=$_.BoundingRect.Y+$region.y;width=$_.BoundingRect.Width;height=$_.BoundingRect.Height}})
                if($words.Count -eq 0){continue}
                $key=$line.Text+'|'+[Math]::Round($words[0].x)+'|'+[Math]::Round($words[0].y)
                if($seen.Add($key)){$lines.Add([ordered]@{text=$line.Text;words=$words})}
            }
        }finally{if(-not $region.full -and $null -ne $sample){$sample.Dispose()}}
    }
    $out=[ordered]@{valid=$true;method='winrt-fixed-horizontal-bands-v1';language=$engine.RecognizerLanguage.LanguageTag;source_sha256=(Get-FileHash -LiteralPath $ImagePath -Algorithm SHA256).Hash.ToLowerInvariant();width=$width;height=$height;text=(@($lines|ForEach-Object{$_.text})-join ' ');lines=@($lines);regions=$regions}
    $json=$out | ConvertTo-Json -Depth 8
    if($OutputPath){[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),$json,[Text.UTF8Encoding]::new($false))}
    $json
} finally {
    if($null -ne $bitmap){$bitmap.Dispose()}
    $stream.Dispose()
}
