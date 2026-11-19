# Author host utility. Only a caller-owned cold project may be passed here.
# ProductName is preserved verbatim; no source or delivered EXE is rewritten.
$script:ScopedIdentityRepository=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path.TrimEnd('\')
function Set-ScopedUnityIdentity {
  param([Parameter(Mandatory)][string]$Project,[Parameter(Mandatory)][string]$RunId)
  if($RunId-notmatch'^[A-Za-z0-9][A-Za-z0-9._-]{0,159}$'){throw 'Unsafe Unity identity run id.'}
  $repo=$script:ScopedIdentityRepository
  $projectFull=[IO.Path]::GetFullPath($Project).TrimEnd('\')
  if(-not$projectFull.StartsWith($repo+'\tmp\',[StringComparison]::OrdinalIgnoreCase)){throw 'Unity identity may change only a repository-owned cold tmp project.'}
  $path=Join-Path $projectFull 'ProjectSettings\ProjectSettings.asset'
  $text=[IO.File]::ReadAllText($path)
  $companyMatches=[regex]::Matches($text,'(?m)^  companyName:.*$');$productMatches=[regex]::Matches($text,'(?m)^  productName:[ \t]*(.*)$')
  if($companyMatches.Count-ne1-or$productMatches.Count-ne1){throw 'Unity identity properties are missing or ambiguous.'}
  $productLine=$productMatches[0].Value;$raw=$productMatches[0].Groups[1].Value.Trim()
  if($raw.StartsWith('"')){$product=[string]($raw|ConvertFrom-Json)}elseif($raw.StartsWith("'")){$product=$raw.Substring(1,$raw.Length-2).Replace("''","'")}else{$product=$raw}
  if([string]::IsNullOrWhiteSpace($product)){throw 'Cannot bind an empty candidate productName.'}
  $company='GameCreateBenchmarkTemp-'+$RunId
  $updated=[regex]::Replace($text,'(?m)^  companyName:.*$','  companyName: '+$company)
  if([regex]::Match($updated,'(?m)^  productName:.*$').Value-cne[regex]::Match($text,'(?m)^  productName:.*$').Value){throw 'Host attempted to change productName.'}
  [IO.File]::WriteAllText($path,$updated,[Text.UTF8Encoding]::new($false))
  $localLow=[IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) '..\LocalLow')).TrimEnd('\')
  [ordered]@{company=$company;product=$product;product_line_preserved=$true;company_root=(Join-Path $localLow $company);registry_key=('HKCU:\Software\'+$company);scope='only this unique company leaf; arbitrary external candidate storage is not isolated'}
}

function Assert-ScopedIdentityReceipt {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Identity)
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'No actual Unity identity receipt; cannot assume storage isolation.'}
  $lines=@(Get-Content -LiteralPath $Path|Where-Object{-not[string]::IsNullOrWhiteSpace($_)})
  if(-not$lines.Count){throw 'Empty Unity identity observations.'}
  foreach($line in $lines){$row=$line|ConvertFrom-Json;if($row.valid-ne$true-or$row.process_id-le0-or$row.company-cne$Identity.company-or$row.product-cne$Identity.product-or-not([IO.Path]::GetFullPath($row.persistent_path)).StartsWith($Identity.company_root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Actual Unity company/product/persistence differs from the owned identity; observer repair required.'}}
}

function Assert-OwnedCompanyLeaf {
  param([Parameter(Mandatory)]$Identity)
  $base=[IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) '..\LocalLow')).TrimEnd('\')
  $owned=[IO.Path]::GetFullPath($Identity.company_root).TrimEnd('\')
  if($Identity.company-notmatch'^GameCreateBenchmarkTemp-[A-Za-z0-9][A-Za-z0-9._-]{0,159}$'-or(Split-Path -Parent $owned)-cne$base-or(Split-Path -Leaf $owned)-cne$Identity.company){throw 'Refuse cleanup outside the exact run-owned company leaf.'}
  return $owned
}
