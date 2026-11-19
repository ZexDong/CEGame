[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,
    [string]$UnityEditorPath=$env:UNITY_EDITOR,
    [string]$OutputDirectory = ""
)

& (Join-Path $PSScriptRoot "run-phase.ps1") `
    -ProjectPath $ProjectPath `
    -Phase Static `
    -UnityEditorPath $UnityEditorPath `
    -OutputDirectory $OutputDirectory
exit $LASTEXITCODE
