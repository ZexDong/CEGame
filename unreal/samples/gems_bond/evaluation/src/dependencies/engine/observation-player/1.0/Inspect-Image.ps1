param([Parameter(Mandatory)][string]$Path)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$bitmap=[Drawing.Bitmap]::new([IO.Path]::GetFullPath($Path))
try {
    $count=0; $bright=0; $sum=0.0
    for($y=0;$y -lt $bitmap.Height;$y+=8){for($x=0;$x -lt $bitmap.Width;$x+=8){
        $p=$bitmap.GetPixel($x,$y);$v=([double]$p.R+$p.G+$p.B)/3;$sum+=$v;$count++;if($v -gt 20){$bright++}
    }}
    @{width=$bitmap.Width;height=$bitmap.Height;mean_luminance=$sum/$count;bright_fraction=$bright/$count;black=($bright/$count -lt 0.01)} | ConvertTo-Json -Compress
} finally { $bitmap.Dispose() }
