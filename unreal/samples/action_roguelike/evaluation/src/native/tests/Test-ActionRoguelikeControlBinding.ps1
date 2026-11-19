[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'scripts/ActionRoguelikeStateAdapter.ps1')
$source=Join-Path $root 'scripts/Invoke-ActionRoguelikeCanonicalEvaluation.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Evaluator syntax is invalid.'}
foreach($name in @('Get-ControlActivation','Get-ControlActivations')){
    $definition=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    Invoke-Expression $definition.Extent.Text
}
$snapshot=('{"controls":[{"semantic_action":"primary_attack","activation":{"kind":"keyboard","physical_control":"LeftMouseButton"}},{"semantic_action":"black_hole","activation":{"kind":"mouse","mouse_button":"right"}},{"semantic_action":"teleport","activation":{"kind":"keyboard","physical_control":"Q"}},{"semantic_action":"restart","activation":{"kind":"keyboard","physical_control":"R"}}]}'|ConvertFrom-Json -Depth 10)
$primary=Get-ControlActivation $snapshot 'primary_attack'
$black=Get-ControlActivation $snapshot 'black_hole'
$restart=Get-ControlActivation $snapshot 'restart'
if($null-eq$primary -or $primary.kind-ne'mouse' -or $primary.button-ne'Left'){throw 'A schema-valid string control did not resolve to a mouse input.'}
if($black.button-ne'Right' -or $restart.key-ne'R'){throw 'Public mouse/keyboard bindings did not resolve.'}
if($null-ne(Get-ControlActivation $snapshot 'absent')){throw 'An undocumented fallback was invented.'}
if(@(Get-ControlActivations $snapshot @('primary_attack','black_hole','teleport')).Count-ne3){throw 'Published controls were silently dropped.'}
Write-Output 'ACTIONROGUELIKE_CONTROL_BINDING_OK schema_string_fields=true legacy_mouse_key=true public_mouse=true no_private_fallback=true'
