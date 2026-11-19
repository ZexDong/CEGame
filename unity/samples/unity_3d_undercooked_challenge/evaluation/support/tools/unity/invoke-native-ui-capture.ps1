#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Executable,[Parameter(Mandatory)][string]$OutputRoot)
$ErrorActionPreference='Stop'
$workspace=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$OutputRoot=[IO.Path]::GetFullPath($OutputRoot)
if(-not $OutputRoot.StartsWith($workspace+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'UI capture output escaped the workspace'}
if(Test-Path -LiteralPath $OutputRoot){throw 'UI capture attempt already exists'}
[IO.Directory]::CreateDirectory($OutputRoot)|Out-Null
$info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=[IO.Path]::GetFullPath($Executable);$info.UseShellExecute=$false
# A visible player window is required for actual OS pointer input and frame OCR.
$info.Environment['NOIR_UI_CAPTURE']='1';$info.Environment['NOIR_UI_DIR']=$OutputRoot;$info.Environment['NOIR_STANDALONE_CAPTURE_ENABLED']='0'
foreach($arg in @('-screen-width','1280','-screen-height','720','-screen-fullscreen','0','-logFile',(Join-Path $OutputRoot 'player.log'))){$info.ArgumentList.Add($arg)}
$started=[DateTimeOffset]::UtcNow;$p=[Diagnostics.Process]::Start($info)
try {
 while(-not $p.HasExited){
  foreach($file in @(Get-ChildItem -LiteralPath $OutputRoot -Filter '*.request.json' -File)){
   $id=$file.Name.Replace('.request.json','');$replyPath=Join-Path $OutputRoot ($id+'.reply.json')
   if(Test-Path -LiteralPath $replyPath){continue}
   try{$req=Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json}catch{continue}
   $image=[IO.Path]::GetFullPath([string]$req.image)
   if(-not $image.StartsWith($OutputRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'UI request path escaped the capture directory'}
   $ocrPath=Join-Path $OutputRoot ($id+'.ocr.json')
   $ocrText=& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -File (Join-Path $PSScriptRoot 'read-image-text.ps1') -ImagePath $image -OutputPath $ocrPath
   if($LASTEXITCODE -ne 0){throw "OCR failed for $id"}
   $ocr=($ocrText -join [Environment]::NewLine)|ConvertFrom-Json
   $reply=[ordered]@{valid=[bool]$ocr.valid;found=$false;x=0;y=0;text=[string]$ocr.text;error=''}
   $pattern=switch([string]$req.token){'START'{'\b(START|PLAY|BEGIN)\b'} 'RESUME'{'\b(RESUME|CONTINUE)\b'} 'RESTART'{'\b(RESTART|RETRY)\b'} 'RETURN'{'\b(RETURN|MENU)\b'} default{''}}
   if($pattern){
    $word=@($ocr.lines | ForEach-Object {$_.words} | Where-Object { [string]$_.text -match $pattern } | Select-Object -First 1)
    if($word.Count){$reply.found=$true;$reply.x=[double]$word[0].x+[double]$word[0].width/2;$reply.y=[double]$word[0].y+[double]$word[0].height/2}
   }
   [IO.File]::WriteAllText($replyPath,($reply|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
  }
  if(([DateTimeOffset]::UtcNow-$started).TotalSeconds -gt 150){throw 'Native UI capture exceeded its bounded attempt'}
  $null=$p.WaitForExit(100)
 }
 $p.Refresh();if($p.ExitCode -ne 0){throw "Native UI capture exited $($p.ExitCode). See $OutputRoot\player.log"}
 $runtime=Get-Content -LiteralPath (Join-Path $OutputRoot 'ui-runtime.json') -Raw | ConvertFrom-Json
 if(-not $runtime.valid){throw "Native UI observation failed: $($runtime.error)"}
 $states=@();foreach($frame in $runtime.frames){
  $ocr=Get-Content -LiteralPath (Join-Path $OutputRoot ($frame.id+'.ocr.json')) -Raw | ConvertFrom-Json
  $symbols=& $env:GAMECREATE_PYTHON (Join-Path $PSScriptRoot 'read-symbol-hud.py') --image (Join-Path $OutputRoot $frame.path) --ocr (Join-Path $OutputRoot ($frame.id+'.ocr.json')) --output (Join-Path $OutputRoot ($frame.id+'.symbols.json'))
  if($LASTEXITCODE -ne 0){throw "Symbol observation failed for $($frame.id)"}
  $symbols=($symbols -join [Environment]::NewLine)|ConvertFrom-Json
  $states+=[ordered]@{id=$frame.id;phase=$frame.phase;room=$frame.room;bonds=$frame.bonds;charges=$frame.charges;alive=$frame.alive;frame=$frame.frame;text=([string]$ocr.text).Normalize([Text.NormalizationForm]::FormKC);source_sha256=$ocr.source_sha256;language=$ocr.language;image=$frame.path;symbols_valid=$symbols.valid;observed_room=$symbols.observed_room;observed_bonds=$symbols.observed_bonds;observed_charges=$symbols.observed_charges}
 }
 $result=[ordered]@{valid=$true;process_id=$runtime.process_id;profile=$runtime.profile;product_block_reason=$(if($null-ne$runtime.PSObject.Properties['product_block_reason']){[string]$runtime.product_block_reason}else{''});menu_click=$runtime.menu_click;pause_resume_click=$runtime.pause_resume_click;pause_restart_click=$runtime.pause_restart_click;success_return_click=$runtime.success_return_click;menu_world_clean=$runtime.menu_world_clean;initial_world_clean=$runtime.initial_world_clean;states=$states}
 [IO.File]::WriteAllText((Join-Path $OutputRoot 'ui-observations.json'),($result|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
 [pscustomobject]$result | Select-Object valid,process_id,menu_click,pause_resume_click,pause_restart_click,success_return_click,menu_world_clean | ConvertTo-Json
} finally {if(-not $p.HasExited){$p.Kill($true);$null=$p.WaitForExit(10000)};$p.Dispose()}
