[CmdletBinding()]
param([string]$InputRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$gatePath = Join-Path $InputRoot 'tools/Test-PublicInput.ps1'
$tokens = $null
$parseErrors = $null
$syntax = [Management.Automation.Language.Parser]::ParseFile($gatePath, [ref]$tokens, [ref]$parseErrors)
if (@($parseErrors).Count -ne 0) {
    throw 'The public input gate must parse before asset regression tests run.'
}
foreach ($functionName in @('Assert-PublicInput', 'Test-FbxArtPayload')) {
    $definition = $syntax.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $functionName }, $true)
    if ($null -eq $definition) {
        throw "Missing gate function: $functionName"
    }
    Invoke-Expression $definition.Extent.Text
}

$fixturePath = [IO.Path]::GetTempFileName()
try {
    $basePath = Join-Path $InputRoot 'assets/files/Manny/AS_manny_standblock.fbx'
    $baseText = [IO.File]::ReadAllText($basePath)
    Test-FbxArtPayload -Path $basePath -Kind 'animation_sequence'
    $hostPath = ([string][char]67) + [char]58 + [char]47 + 'private-export.fbx'
    $cases = @(
        @{ name = 'custom_animation_channel'; suffix = 'C: "OP",1,2, "Damage"'; expected = 'Custom animation channel' },
        @{ name = 'source_package_reference'; suffix = '/Game/Unexpected'; expected = 'Source implementation metadata' },
        @{ name = 'host_path_metadata'; suffix = $hostPath; expected = 'Host path' },
        @{ name = 'non_english_metadata'; suffix = [string][char]0x4e00; expected = 'Non-ASCII' },
        @{ name = 'non_art_object'; suffix = ([string][char]9) + 'Script: 1, "Script::Unexpected", ""'; expected = 'Non-art object' },
        @{ name = 'mesh_inside_animation'; suffix = ([string][char]9) + 'Geometry: 1, "Geometry::Unexpected", "Mesh"'; expected = 'Animation-only FBX contains mesh data' }
    )
    foreach ($case in $cases) {
        [IO.File]::WriteAllText($fixturePath, ($baseText + [Environment]::NewLine + $case.suffix), [Text.UTF8Encoding]::new($false))
        $failure = $null
        try {
            Test-FbxArtPayload -Path $fixturePath -Kind 'animation_sequence'
        }
        catch {
            $failure = $_.Exception.Message
        }
        if ($null -eq $failure -or -not $failure.Contains($case.expected)) {
            throw "Asset gate did not reject $($case.name) for the expected reason."
        }
    }
    Write-Output "ASSET_PAYLOAD_REGRESSION_OK valid=1 rejected=$($cases.Count)"
}
finally {
    Remove-Item -LiteralPath $fixturePath -Force
}
