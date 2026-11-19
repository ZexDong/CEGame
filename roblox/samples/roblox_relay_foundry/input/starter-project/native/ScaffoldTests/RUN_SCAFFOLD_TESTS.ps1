param([string]$OutputDirectory = '')
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$project = Join-Path $root 'project\default.project.json'
$source = Join-Path $root 'project\src'
$rojo = Join-Path $root 'Tools\rojo.exe'
$compiler = Join-Path $root 'Tools\luau-compile.exe'
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $PSScriptRoot ('results\' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$place = Join-Path $OutputDirectory 'RelayFoundryScaffoldSmoke.rbxlx'
$started = [DateTimeOffset]::UtcNow
$compileResults = @()
$status = 'pass'
$failure = $null
$rojoVersion = $null
$buildText = $null
$buildExit = $null
$placeHash = $null
try {
    foreach ($required in @($project, $source, $rojo, $compiler)) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Missing required path: $required" }
    }
    $rojoVersion = (& $rojo --version | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Rojo version command failed: $LASTEXITCODE" }
    $scripts = @(Get-ChildItem -LiteralPath $source -Recurse -File -Filter '*.luau' | Sort-Object FullName)
    if ($scripts.Count -eq 0) { throw 'No Luau source files were discovered.' }
    foreach ($script in $scripts) {
        $text = (& $compiler --null $script.FullName 2>&1 | Out-String).Trim()
        $code = $LASTEXITCODE
        $compileResults += [ordered]@{
            path = $script.FullName.Substring($root.Length + 1).Replace('\','/')
            exit_code = $code
            diagnostics = $text
        }
        if ($code -ne 0) { throw "Luau compile failed: $($script.FullName)" }
    }
    $buildText = (& $rojo build $project -o $place 2>&1 | Out-String).Trim()
    $buildExit = $LASTEXITCODE
    if ($buildExit -ne 0) { throw "Rojo build failed: $buildExit" }
    if (-not (Test-Path -LiteralPath $place)) { throw 'Rojo did not create the RBXLX output.' }
    $placeItem = Get-Item -LiteralPath $place
    if ($placeItem.Length -le 0) { throw 'Generated RBXLX is empty.' }
    [xml](Get-Content -LiteralPath $place -Raw) | Out-Null
    $placeHash = (Get-FileHash -LiteralPath $place -Algorithm SHA256).Hash
} catch {
    $status = 'fail'
    $failure = $_.Exception.Message
}
$finished = [DateTimeOffset]::UtcNow
$result = [ordered]@{
    schema_version = 1
    status = $status
    started_utc = $started.ToString('o')
    finished_utc = $finished.ToString('o')
    elapsed_seconds = [Math]::Round(($finished - $started).TotalSeconds, 3)
    checks = [ordered]@{
        tool_files_present = (Test-Path -LiteralPath $rojo) -and (Test-Path -LiteralPath $compiler)
        luau_compile = $compileResults
        rojo_version = $rojoVersion
        rojo_build_exit_code = $buildExit
        rojo_build_output = $buildText
        rbxlx_bytes = if (Test-Path -LiteralPath $place) { (Get-Item -LiteralPath $place).Length } else { 0 }
        rbxlx_sha256 = $placeHash
        rbxlx_xml_parse = [bool]$placeHash
    }
    scope = 'compile_build_and_serialization_only'
    studio_play = 'not_run'
    full_gameplay = 'not_run'
    failure = $failure
}
$resultPath = Join-Path $OutputDirectory 'public_scaffold_result.json'
[IO.File]::WriteAllText($resultPath, ($result | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
Write-Host "Public scaffold result: $resultPath"
Write-Host ($result | ConvertTo-Json -Depth 20)
if ($status -ne 'pass') { exit 1 }
