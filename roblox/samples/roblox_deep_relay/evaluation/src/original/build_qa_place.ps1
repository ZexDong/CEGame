param(
    [Parameter(Mandatory = $true)][string]$ProjectDirectory,
    [Parameter(Mandatory = $true)][string]$OutputPlace,
    [Parameter(Mandatory = $true)][string]$FormalRunnerSource,
    [Parameter(Mandatory = $true)][string]$ObserverSource,
    [Parameter(Mandatory = $true)][string]$GeneratedProject,
    [Parameter(Mandatory = $true)][string]$Rojo
)

$ErrorActionPreference = 'Stop'
$projectDirectory = (Resolve-Path -LiteralPath $ProjectDirectory).Path
$sourceProject = Join-Path $projectDirectory 'default.project.json'
$formalRunner = (Resolve-Path -LiteralPath $FormalRunnerSource).Path
$observer = (Resolve-Path -LiteralPath $ObserverSource).Path
$rojoPath = (Resolve-Path -LiteralPath $Rojo).Path
$outputParent = Split-Path -Parent $OutputPlace
$generatedParent = Split-Path -Parent $GeneratedProject

if (-not (Test-Path -LiteralPath $sourceProject)) { throw "Missing $sourceProject" }
New-Item -ItemType Directory -Force -Path $outputParent,$generatedParent | Out-Null

$project = Get-Content -Raw -Encoding UTF8 -LiteralPath $sourceProject | ConvertFrom-Json

function Convert-PathsToAbsolute([object]$Node) {
    if ($null -eq $Node) { return }
    if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string] -and $Node -isnot [pscustomobject]) {
        foreach ($item in $Node) { Convert-PathsToAbsolute $item }
        return
    }
    if ($Node -is [pscustomobject]) {
        foreach ($property in @($Node.PSObject.Properties)) {
            if ($property.Name -eq '$path') {
                $candidatePath = Join-Path $projectDirectory ([string]$property.Value)
                $property.Value = (Resolve-Path -LiteralPath $candidatePath).Path
            } else {
                Convert-PathsToAbsolute $property.Value
            }
        }
    }
}

Convert-PathsToAbsolute $project
if (-not $project.tree.StarterPlayer) {
    $project.tree | Add-Member -NotePropertyName StarterPlayer -NotePropertyValue ([pscustomobject]@{})
}
if (-not $project.tree.StarterPlayer.StarterPlayerScripts) {
    $project.tree.StarterPlayer | Add-Member -NotePropertyName StarterPlayerScripts -NotePropertyValue ([pscustomobject]@{})
}
$project.tree.StarterPlayer.StarterPlayerScripts | Add-Member -Force -NotePropertyName DeepRelayQAObserver -NotePropertyValue ([pscustomobject]@{'$path'=$observer})
$project.tree.StarterPlayer.StarterPlayerScripts | Add-Member -Force -NotePropertyName DeepRelayFormalEvaluator -NotePropertyValue ([pscustomobject]@{'$path'=$formalRunner})

$json = $project | ConvertTo-Json -Depth 60
[System.IO.File]::WriteAllText($GeneratedProject, $json, [System.Text.UTF8Encoding]::new($false))
& $rojoPath build $GeneratedProject -o $OutputPlace
if ($LASTEXITCODE -ne 0) { throw "Rojo build failed with exit code $LASTEXITCODE" }

$stream = [System.IO.File]::OpenRead($OutputPlace)
try {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = ([System.BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '') }
    finally { $sha.Dispose() }
} finally { $stream.Dispose() }

Write-Host "QA place built: $OutputPlace"
Write-Host "QA place SHA-256: $hash"
Write-Host "Generated QA project: $GeneratedProject"
Write-Host 'Candidate source and delivered RBXLX were not modified.'
