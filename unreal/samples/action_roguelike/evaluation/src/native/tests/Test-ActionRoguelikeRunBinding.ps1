[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/ActionRoguelikeRunBinding.ps1')

$script:checks = 0
function Assert-Binding([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    ++$script:checks
}
function Write-Fixture([string]$Path, [string]$Content) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}
function Write-FixtureJson([string]$Path, $Value) { Write-Fixture $Path ($Value | ConvertTo-Json -Depth 30) }
function Assert-PathRejected([string]$ManifestPath, [string]$RelativePath) {
    $rejected = $false
    try { [void](Resolve-ActionRoguelikeManifestPath -ManifestPath $ManifestPath -RelativePath $RelativePath -AllowMissing) } catch { $rejected = $true }
    Assert-Binding $rejected "An unsafe manifest path was accepted: $RelativePath"
}

$temporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixtureRoot = Join-Path $temporaryParent ('actionroguelike-run-binding-' + [guid]::NewGuid().ToString('N'))
$links = [Collections.Generic.List[string]]::new()
try {
    $inputRoot = Join-Path $fixtureRoot 'relocated input'
    $manifestPath = Join-Path $inputRoot 'BENCHMARK_MANIFEST.json'
    $projectPath = Join-Path $inputRoot 'custom game/Renamed.uproject'
    $candidateManifest = @{ paths = @{ project_root = 'custom game'; project_file = 'custom game/Renamed.uproject' } }
    Write-FixtureJson $manifestPath $candidateManifest
    Write-FixtureJson $projectPath @{ FileVersion = 3; EngineAssociation = '5.6' }
    $binding = Resolve-ActionRoguelikeCandidateBinding -CandidateProject $inputRoot
    Assert-Binding ($binding.success -and $binding.project_file -eq $projectPath -and $binding.input_root -eq $inputRoot) 'A relocated input did not resolve its manifest project.'
    $binding = Resolve-ActionRoguelikeCandidateBinding -CandidateProject (Split-Path -Parent $projectPath)
    Assert-Binding ($binding.success -and $binding.source -eq 'candidate_manifest') 'A project directory did not resolve its related ancestor manifest.'
    $otherProject = Join-Path $inputRoot 'custom game/Explicit.uproject'
    Write-FixtureJson $otherProject @{ FileVersion = 3 }
    $binding = Resolve-ActionRoguelikeCandidateBinding -CandidateProject $otherProject
    Assert-Binding ($binding.success -and $binding.project_file -eq $otherProject -and $binding.manifest_path_matches_candidate -eq $false) 'A manifest overrode an explicit project file.'
    $missing = Join-Path $inputRoot 'custom game/Missing.uproject'
    $binding = Resolve-ActionRoguelikeCandidateBinding -CandidateProject $missing
    Assert-Binding (-not $binding.success -and $binding.project_file -eq $missing -and $binding.reason_code -eq 'CANDIDATE_PROJECT_MISSING' -and $binding.attribution -eq 'candidate') 'A missing explicit project was replaced or misattributed.'
    $unrelatedProject = Join-Path $inputRoot 'unrelated/Detached.uproject'
    Write-FixtureJson $unrelatedProject @{ FileVersion = 3 }
    $binding = Resolve-ActionRoguelikeCandidateBinding -CandidateProject $unrelatedProject
    Assert-Binding ($binding.success -and $null -eq $binding.manifest_path -and $binding.project_file -eq $unrelatedProject) 'An unrelated ancestor manifest influenced the explicit project.'

    $bareRoot = Join-Path $fixtureRoot 'bare'
    $bareProject = Join-Path $bareRoot 'Only.uproject'
    Write-FixtureJson $bareProject @{ FileVersion = 3 }
    $binding = Resolve-ActionRoguelikeCandidateBinding -CandidateProject $bareRoot
    Assert-Binding ($binding.success -and $binding.source -eq 'unique_project_file') 'A standalone project directory could not bind.'
    Write-FixtureJson (Join-Path $bareRoot 'Second.uproject') @{ FileVersion = 3 }
    $binding = Resolve-ActionRoguelikeCandidateBinding -CandidateProject $bareRoot
    Assert-Binding (-not $binding.success -and $binding.reason_code -eq 'CANDIDATE_PROJECT_AMBIGUOUS') 'An ambiguous project directory silently selected a project.'
    Write-Fixture (Join-Path $fixtureRoot 'broken/Broken.uproject') '{'
    $binding = Resolve-ActionRoguelikeCandidateBinding -CandidateProject (Join-Path $fixtureRoot 'broken/Broken.uproject')
    Assert-Binding (-not $binding.success -and $binding.reason_code -eq 'CANDIDATE_DESCRIPTOR_INVALID') 'Malformed descriptor JSON was accepted.'
    Write-Fixture (Join-Path $fixtureRoot 'broken/Array.uproject') '[]'
    $binding = Resolve-ActionRoguelikeCandidateBinding -CandidateProject (Join-Path $fixtureRoot 'broken/Array.uproject')
    Assert-Binding (-not $binding.success -and $binding.reason_code -eq 'CANDIDATE_DESCRIPTOR_INVALID') 'A nonobject descriptor was accepted.'
    $absentRoot = Join-Path $fixtureRoot 'missing input'
    $binding = Resolve-ActionRoguelikeCandidateBinding -CandidateProject $absentRoot
    Assert-Binding (-not $binding.success -and $binding.attribution -eq 'candidate' -and $binding.reason_code -eq 'CANDIDATE_PROJECT_MISSING') 'An absent candidate directory became an infrastructure fault.'

    Assert-PathRejected $manifestPath '../outside.uproject'
    Assert-PathRejected $manifestPath '../relocated input sibling/outside.uproject'
    Assert-PathRejected $manifestPath $projectPath
    Assert-PathRejected $manifestPath 'custom game/Renamed.uproject:alternate'
    $escapeRoot = Join-Path $fixtureRoot 'escape'
    Write-FixtureJson (Join-Path $escapeRoot 'BENCHMARK_MANIFEST.json') @{ paths = @{ project_file = '../bare/Only.uproject'; project_root = '../bare' } }
    $binding = Resolve-ActionRoguelikeCandidateBinding -CandidateProject $escapeRoot
    Assert-Binding (-not $binding.success -and $binding.reason_code -eq 'CANDIDATE_PROJECT_BINDING_INVALID') 'A manifest escaped its input root.'
    $missingRoot = Join-Path $fixtureRoot 'manifest-missing'
    Write-FixtureJson (Join-Path $missingRoot 'BENCHMARK_MANIFEST.json') @{ paths = @{ project_file = 'game/Lost.uproject'; project_root = 'game' } }
    $binding = Resolve-ActionRoguelikeCandidateBinding -CandidateProject $missingRoot
    Assert-Binding (-not $binding.success -and $binding.reason_code -eq 'CANDIDATE_PROJECT_MISSING') 'A missing manifest project was not a candidate defect.'

    # Windows junction creation does not need Developer Mode or admin rights.
    $link = Join-Path $inputRoot 'linked'
    if ([IO.Path]::DirectorySeparatorChar -eq '\') { [void](New-Item -ItemType Junction -Path $link -Target $bareRoot) }
    else { [void](New-Item -ItemType SymbolicLink -Path $link -Target $bareRoot) }
    $links.Add($link)
    Assert-PathRejected $manifestPath 'linked/Only.uproject'
    Assert-PathRejected $manifestPath 'linked/NotYetCreated.uproject'
    $binding = Resolve-ActionRoguelikeCandidateBinding -CandidateProject (Join-Path $link 'Only.uproject')
    Assert-Binding (-not $binding.success -and $binding.reason_code -eq 'CANDIDATE_PROJECT_BINDING_INVALID') 'An explicit project traversed a reparse point.'

    $target = Resolve-ActionRoguelikeEditorTarget -ProjectFile $projectPath
    Assert-Binding ($target.success -and $target.target_name -eq 'UnrealEditor' -and -not $target.build_required) 'A content-only project invented a code target.'
    $codeProject = Join-Path $fixtureRoot 'code/Renamed.uproject'
    Write-FixtureJson $codeProject @{ Modules = @(@{ Name = 'Gameplay'; Type = 'Runtime' }) }
    $target = Resolve-ActionRoguelikeEditorTarget -ProjectFile $codeProject
    Assert-Binding (-not $target.success -and $target.reason_code -eq 'CANDIDATE_EDITOR_TARGET_MISSING') 'A nonexistent module-derived Editor target was invented.'
    $editorTarget = Join-Path $fixtureRoot 'code/Source/CustomHost.Target.cs'
    Write-Fixture $editorTarget 'public class CustomHostTarget : TargetRules { public CustomHostTarget(TargetInfo info) : base(info) { Type = TargetType.Editor; } }'
    $target = Resolve-ActionRoguelikeEditorTarget -ProjectFile $codeProject
    Assert-Binding ($target.success -and $target.target_name -eq 'CustomHost' -and $target.target_file -eq $editorTarget -and $target.build_required) 'An Editor target without an Editor filename suffix was not selected.'
    Write-Fixture (Join-Path $fixtureRoot 'code/Source/CommentEditor.Target.cs') 'public class CommentEditorTarget : TargetRules { /* Type = TargetType.Editor; */ string text = "Type = TargetType.Editor;"; }'
    $target = Resolve-ActionRoguelikeEditorTarget -ProjectFile $codeProject
    Assert-Binding ($target.success -and $target.target_name -eq 'CustomHost') 'Comments or string literals became Editor targets.'
    Write-Fixture (Join-Path $fixtureRoot 'code/Source/SecondEditor.Target.cs') 'public class SecondEditorTarget : TargetRules { public SecondEditorTarget(TargetInfo info) : base(info) { Type = TargetType.Editor; } }'
    $target = Resolve-ActionRoguelikeEditorTarget -ProjectFile $codeProject
    Assert-Binding (-not $target.success -and $target.reason_code -eq 'CANDIDATE_EDITOR_TARGET_AMBIGUOUS' -and $target.candidates.Count -eq 2) 'Ambiguous Editor targets silently selected the first file.'
    $sourceLink = Join-Path $fixtureRoot 'code/Source/External'
    if ([IO.Path]::DirectorySeparatorChar -eq '\') { [void](New-Item -ItemType Junction -Path $sourceLink -Target $bareRoot) }
    else { [void](New-Item -ItemType SymbolicLink -Path $sourceLink -Target $bareRoot) }
    $links.Add($sourceLink)
    $target = Resolve-ActionRoguelikeEditorTarget -ProjectFile $codeProject
    Assert-Binding (-not $target.success -and $target.reason_code -eq 'CANDIDATE_EDITOR_TARGET_INVALID') 'Source target traversal accepted a reparse point.'

    $engineRoot = Join-Path $fixtureRoot 'installed engine'
    $repositoryRoot = Join-Path $fixtureRoot 'repository'
    $versionPath = Join-Path $engineRoot 'Engine/Build/Build.version'
    $buildVersion = @{ MajorVersion = 5; MinorVersion = 6; PatchVersion = 1; Changelist = 44394996 }
    Write-FixtureJson $versionPath $buildVersion
    foreach ($relative in @('Engine/Binaries/Win64/UnrealEditor.exe', 'Engine/Binaries/Win64/UnrealEditor-Cmd.exe', 'Engine/Build/BatchFiles/Build.bat')) { Write-Fixture (Join-Path $engineRoot $relative) 'fixture; never executed' }
    $executorRelative = 'engine/unreal-5.6.1/executor/UnrealEvaluationExecutor.psm1'
    $executor = Join-Path $repositoryRoot $executorRelative
    Write-Fixture $executor '# fixture executor; never imported'
    Write-Fixture (Join-Path $repositoryRoot 'engine/unreal-5.7.4/executor/UnrealEvaluationExecutor.psm1') '# newer executor must never be selected'
    $trustedManifest = @{ engine = @{ version = '5.6.1'; changelist = 44394996 }; tooling = @{ identities = @{ executor_module = @{ path = $executorRelative; sha256 = (Get-FileHash -LiteralPath $executor -Algorithm SHA256).Hash } } } }
    $binding = Resolve-ActionRoguelikeEngineBinding -RepositoryRoot $repositoryRoot -EngineRoot $engineRoot -Manifest $trustedManifest
    Assert-Binding ($binding.success -and $binding.executor_path -eq $executor -and $binding.version -eq '5.6.1' -and $binding.changelist -eq 44394996) 'An exact engine/executor binding did not resolve.'
    $buildVersion.PatchVersion = 2; Write-FixtureJson $versionPath $buildVersion
    $binding = Resolve-ActionRoguelikeEngineBinding -RepositoryRoot $repositoryRoot -EngineRoot $engineRoot -Manifest $trustedManifest
    Assert-Binding (-not $binding.success -and $binding.reason_code -eq 'HOST_ENGINE_IDENTITY_MISMATCH' -and $binding.attribution -eq 'host') 'A wrong engine patch was accepted or attributed to the candidate.'
    $buildVersion.PatchVersion = 1; $buildVersion.Changelist = 44394997; Write-FixtureJson $versionPath $buildVersion
    $binding = Resolve-ActionRoguelikeEngineBinding -RepositoryRoot $repositoryRoot -EngineRoot $engineRoot -Manifest $trustedManifest
    Assert-Binding (-not $binding.success -and $binding.reason_code -eq 'HOST_ENGINE_IDENTITY_MISMATCH') 'A wrong engine changelist was accepted.'
    $buildVersion.Changelist = 44394996; Write-FixtureJson $versionPath $buildVersion
    $trustedManifest.tooling.identities.executor_module.sha256 = '0' * 64
    $binding = Resolve-ActionRoguelikeEngineBinding -RepositoryRoot $repositoryRoot -EngineRoot $engineRoot -Manifest $trustedManifest
    Assert-Binding (-not $binding.success -and $binding.reason_code -eq 'TOOLING_EXECUTOR_IDENTITY_MISMATCH' -and $binding.attribution -eq 'tooling') 'A modified executor was accepted or attributed to the candidate.'
    $trustedManifest.tooling.identities.executor_module.sha256 = (Get-FileHash -LiteralPath $executor -Algorithm SHA256).Hash
    $trustedManifest.tooling.identities.executor_module.path = 'engine/unreal-5.7.4/executor/UnrealEvaluationExecutor.psm1'
    $binding = Resolve-ActionRoguelikeEngineBinding -RepositoryRoot $repositoryRoot -EngineRoot $engineRoot -Manifest $trustedManifest
    Assert-Binding (-not $binding.success -and $binding.reason_code -eq 'TOOLING_EXECUTOR_VERSION_MISMATCH') 'A manifest could bind another engine version executor.'
    $trustedManifest.tooling.identities.executor_module.path = $executorRelative
    $withoutExactExecutor = Join-Path $fixtureRoot 'repository without exact version'
    Write-Fixture (Join-Path $withoutExactExecutor 'engine/unreal-5.7.4/executor/UnrealEvaluationExecutor.psm1') '# fallback forbidden'
    $binding = Resolve-ActionRoguelikeEngineBinding -RepositoryRoot $withoutExactExecutor -EngineRoot $engineRoot -Manifest $trustedManifest
    Assert-Binding (-not $binding.success -and $binding.reason_code -eq 'TOOLING_EXECUTOR_MISSING' -and $null -eq $binding.executor_path) 'The missing exact executor fell back to a different version.'
    $trustedManifest.engine.version = '5.6'
    $binding = Resolve-ActionRoguelikeEngineBinding -RepositoryRoot $repositoryRoot -EngineRoot $engineRoot -Manifest $trustedManifest
    Assert-Binding (-not $binding.success -and $binding.reason_code -eq 'TOOLING_MANIFEST_ENGINE_INVALID') 'A nonexact engine version was accepted.'
    $trustedManifest.engine.version = '5.6.1'
    Write-Fixture $versionPath '{'
    $binding = Resolve-ActionRoguelikeEngineBinding -RepositoryRoot $repositoryRoot -EngineRoot $engineRoot -Manifest $trustedManifest
    Assert-Binding (-not $binding.success -and $binding.reason_code -eq 'HOST_ENGINE_INVALID') 'Malformed Build.version was accepted.'
    Write-FixtureJson $versionPath @{ MajorVersion = 5; MinorVersion = 6; PatchVersion = 1 }
    $binding = Resolve-ActionRoguelikeEngineBinding -RepositoryRoot $repositoryRoot -EngineRoot $engineRoot -Manifest $trustedManifest
    Assert-Binding (-not $binding.success -and $binding.reason_code -eq 'HOST_ENGINE_INVALID') 'Build.version without a changelist was accepted.'
    Write-FixtureJson $versionPath $buildVersion
    $incompleteEngine = Join-Path $fixtureRoot 'incomplete engine'
    Write-FixtureJson (Join-Path $incompleteEngine 'Engine/Build/Build.version') $buildVersion
    $binding = Resolve-ActionRoguelikeEngineBinding -RepositoryRoot $repositoryRoot -EngineRoot $incompleteEngine -Manifest $trustedManifest
    Assert-Binding (-not $binding.success -and $binding.reason_code -eq 'HOST_ENGINE_INCOMPLETE') 'Missing host engine executables were accepted.'
    Write-Output "ACTIONROGUELIKE_RUN_BINDING_OK checks=$script:checks explicit_project_preserved=true manifest_relocation=true reparse_rejected=true editor_target_ambiguity=true exact_engine_executor=true no_unreal_started=true"
} finally {
    # Remove the known test links themselves before removing the fixture tree.
    foreach ($linkPath in $links) {
        if (-not (Test-ActionRoguelikeBindingContainment -Root $fixtureRoot -Path $linkPath)) { throw 'Refusing to remove a link outside the fixture root.' }
        if (Test-Path -LiteralPath $linkPath) { Remove-Item -LiteralPath $linkPath -Force }
    }
    $cleanupRoot = [IO.Path]::GetFullPath($fixtureRoot)
    if (-not (Test-ActionRoguelikeBindingContainment -Root $temporaryParent -Path $cleanupRoot) -or [IO.Path]::GetFileName($cleanupRoot) -notlike 'actionroguelike-run-binding-*') { throw 'Refusing cleanup outside the named temporary fixture root.' }
    if (Test-Path -LiteralPath $cleanupRoot) {
        [void](Assert-ActionRoguelikeBindingPath -Path $cleanupRoot)
        Remove-Item -LiteralPath $cleanupRoot -Recurse -Force
    }
}
