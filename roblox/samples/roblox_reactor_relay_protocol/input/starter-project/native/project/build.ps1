param([string]$Output = "ReactorRelayCandidate.rbxlx")
$ErrorActionPreference = "Stop"
rojo build default.project.json -o $Output
