# Read-only run binding. No candidate script or Target.cs is executed by this file.
Set-StrictMode -Version Latest

function Get-ActionRoguelikeBindingProperty {
    param([AllowNull()]$Value, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Value) { return $null }
    if ($Value -is [Collections.IDictionary]) { return $Value[$Name] }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function Test-ActionRoguelikeBindingContainment {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Path)
    $rootFull = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Root))
    $pathFull = [IO.Path]::GetFullPath($Path)
    $comparison = if ([IO.Path]::DirectorySeparatorChar -eq '\') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $prefix = $rootFull + [IO.Path]::DirectorySeparatorChar
    if ([IO.Path]::EndsInDirectorySeparator($rootFull)) { $prefix = $rootFull }
    return $pathFull.Equals($rootFull, $comparison) -or $pathFull.StartsWith($prefix, $comparison)
}

function Assert-ActionRoguelikeBindingPath {
    param([Parameter(Mandatory)][string]$Path, [string]$Root)
    $full = [IO.Path]::GetFullPath($Path)
    if ($Root -and -not (Test-ActionRoguelikeBindingContainment -Root $Root -Path $full)) {
        throw "Binding path escapes its declared root: $Path"
    }
    # Inspect from the volume root down, before accessing a child through a link.
    # This also rejects a missing leaf beneath an existing junction/symlink.
    $chain = [Collections.Generic.List[string]]::new()
    $current = $full
    while ($current) {
        $chain.Add($current)
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent) { break }
        $current = $parent.FullName
    }
    for ($index = $chain.Count - 1; $index -ge 0; --$index) {
        try { $item = Get-Item -LiteralPath $chain[$index] -Force -ErrorAction Stop }
        catch [Management.Automation.ItemNotFoundException] { continue }
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse points are not permitted in binding paths: $($chain[$index])"
        }
    }
    return $full
}

function Resolve-ActionRoguelikeManifestPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$RelativePath,
        [switch]$AllowMissing
    )
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath) -or $RelativePath.Contains(':')) {
        throw 'A manifest path must be a nonempty relative filesystem path.'
    }
    $manifestFull = Assert-ActionRoguelikeBindingPath -Path $ManifestPath
    $root = Split-Path -Parent $manifestFull
    $full = Assert-ActionRoguelikeBindingPath -Path (Join-Path $root $RelativePath) -Root $root
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $full)) { throw "The manifest-declared path is missing: $RelativePath" }
    return $full
}

function Resolve-ActionRoguelikeCandidateBinding {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CandidateProject)
    $result = [ordered]@{
        success = $false; reason_code = $null; attribution = 'candidate'; detail = ''
        requested_path = $CandidateProject; project_file = $null; project_root = $null
        input_root = $null; manifest_path = $null; manifest = $null; descriptor = $null
        source = $null; manifest_path_matches_candidate = $null
    }
    try {
        $requested = Assert-ActionRoguelikeBindingPath -Path $CandidateProject
        $result.requested_path = $requested
        $explicitProject = [IO.Path]::GetExtension($requested) -ieq '.uproject'
        $isDirectory = Test-Path -LiteralPath $requested -PathType Container
        if (-not $explicitProject -and -not $isDirectory) {
            $result.reason_code = 'CANDIDATE_PROJECT_MISSING'
            $result.detail = 'The supplied project or input directory does not exist.'
            return [pscustomobject]$result
        }
        if ($explicitProject) {
            $result.project_file = $requested
            $result.project_root = Split-Path -Parent $requested
            $result.source = 'explicit_project_file'
            # A missing explicit path stays a candidate defect, even if an
            # ancestor manifest happens to declare another existing project.
            if (-not (Test-Path -LiteralPath $requested -PathType Leaf)) {
                $result.reason_code = 'CANDIDATE_PROJECT_MISSING'
                $result.detail = 'The explicitly selected project file is missing.'
                return [pscustomobject]$result
            }
        }
        $current = if ($isDirectory) { $requested } else { Split-Path -Parent $requested }
        while ($current) {
            $manifestPath = Join-Path $current 'BENCHMARK_MANIFEST.json'
            if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
                $manifestPath = Assert-ActionRoguelikeBindingPath -Path $manifestPath -Root $current
                $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -Depth 100 -ErrorAction Stop
                $paths = Get-ActionRoguelikeBindingProperty $manifest 'paths'
                $declaredFile = [string](Get-ActionRoguelikeBindingProperty $paths 'project_file')
                $declaredRoot = [string](Get-ActionRoguelikeBindingProperty $paths 'project_root')
                $manifestProject = Resolve-ActionRoguelikeManifestPath -ManifestPath $manifestPath -RelativePath $declaredFile -AllowMissing
                $manifestRoot = if ($declaredRoot) { Resolve-ActionRoguelikeManifestPath -ManifestPath $manifestPath -RelativePath $declaredRoot -AllowMissing } else { Split-Path -Parent $manifestProject }
                if (-not (Test-ActionRoguelikeBindingContainment -Root $manifestRoot -Path $manifestProject)) { throw 'The manifest project file is outside its declared project root.' }
                $related = $requested -eq $current -or (Test-ActionRoguelikeBindingContainment -Root $manifestRoot -Path $requested)
                if ($related) {
                    $result.manifest_path = $manifestPath
                    $result.input_root = $current
                    $result.manifest = $manifest
                    if (-not $explicitProject) {
                        $result.project_file = $manifestProject
                        $result.project_root = $manifestRoot
                        $result.source = 'candidate_manifest'
                    }
                    $result.manifest_path_matches_candidate = $result.project_file -eq $manifestProject
                    break
                }
            }
            $parent = [IO.Directory]::GetParent($current)
            if ($null -eq $parent) { break }
            $current = $parent.FullName
        }
        if (-not $result.project_file) {
            $projects = @(Get-ChildItem -LiteralPath $requested -File -Filter '*.uproject' -Force -ErrorAction Stop)
            if ($projects.Count -ne 1) {
                $result.reason_code = if ($projects.Count -eq 0) { 'CANDIDATE_PROJECT_MISSING' } else { 'CANDIDATE_PROJECT_AMBIGUOUS' }
                $result.detail = 'An input manifest or exactly one project file in the supplied directory is required.'
                return [pscustomobject]$result
            }
            $result.project_file = Assert-ActionRoguelikeBindingPath -Path $projects[0].FullName -Root $requested
            $result.project_root = $requested
            $result.source = 'unique_project_file'
        }
        if ([IO.Path]::GetExtension($result.project_file) -ine '.uproject') { throw 'The selected project file must have the .uproject extension.' }
        if (-not (Test-Path -LiteralPath $result.project_file -PathType Leaf)) {
            $result.reason_code = 'CANDIDATE_PROJECT_MISSING'
            $result.detail = 'The manifest-declared project file is missing.'
            return [pscustomobject]$result
        }
        try {
            $descriptor = Get-Content -LiteralPath $result.project_file -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -Depth 100 -ErrorAction Stop
            if ($null -eq $descriptor -or $descriptor -isnot [pscustomobject]) { throw 'A project descriptor must be a JSON object.' }
            $result.descriptor = $descriptor
        } catch {
            $result.reason_code = 'CANDIDATE_DESCRIPTOR_INVALID'
            $result.detail = $_.Exception.Message
            return [pscustomobject]$result
        }
        $result.success = $true
        $result.attribution = $null
        $result.detail = 'The selected project is bound without changing an explicit project selection.'
    } catch {
        $result.reason_code = 'CANDIDATE_PROJECT_BINDING_INVALID'
        $result.detail = $_.Exception.Message
    }
    return [pscustomobject]$result
}

function Resolve-ActionRoguelikeEditorTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectFile, [AllowNull()]$Descriptor)
    $result = [ordered]@{ success = $false; attribution = 'candidate'; reason_code = $null; detail = ''; target_name = $null; target_file = $null; build_required = $true; candidates = @() }
    try {
        $project = Assert-ActionRoguelikeBindingPath -Path $ProjectFile
        if (-not (Test-Path -LiteralPath $project -PathType Leaf)) {
            $result.reason_code = 'CANDIDATE_PROJECT_MISSING'; $result.detail = 'The selected project file is missing.'
            return [pscustomobject]$result
        }
        if ($null -eq $Descriptor) { $Descriptor = Get-Content -LiteralPath $project -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -ErrorAction Stop }
        $root = Split-Path -Parent $project
        $source = Assert-ActionRoguelikeBindingPath -Path (Join-Path $root 'Source') -Root $root
        $targetFiles = [Collections.Generic.List[object]]::new()
        $editors = [Collections.Generic.List[object]]::new()
        if (Test-Path -LiteralPath $source -PathType Container) {
            $pending = [Collections.Generic.Queue[string]]::new(); $pending.Enqueue($source)
            while ($pending.Count -gt 0) {
                foreach ($item in Get-ChildItem -LiteralPath $pending.Dequeue() -Force -ErrorAction Stop) {
                    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Source traversal encountered a reparse point.' }
                    if ($item.PSIsContainer) { $pending.Enqueue($item.FullName); continue }
                    if ($item.Name -notlike '*.Target.cs') { continue }
                    $targetFiles.Add($item)
                    $text = Get-Content -LiteralPath $item.FullName -Raw -Encoding UTF8 -ErrorAction Stop
                    # Strip comments and literals so prose is never mistaken for
                    # a TargetType assignment. Target.cs remains unexecuted.
                    $code = [regex]::Replace($text, '(?ms)//[^\r\n]*|/\*.*?\*/|@"(?:[^"]|"")*"|"(?:\\.|[^"\\])*"|''(?:\\.|[^''\\])*''', ' ')
                    if ($code -match '\bType\s*=\s*(?:UnrealBuildTool\s*\.\s*)?TargetType\s*\.\s*Editor\b') {
                        $name = $item.Name.Substring(0, $item.Name.Length - '.Target.cs'.Length)
                        if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$' -or $code -notmatch ('\bclass\s+' + [regex]::Escape($name + 'Target') + '\s*:\s*(?:UnrealBuildTool\s*\.\s*)?TargetRules\b')) {
                            throw "The Editor target class does not match its file name: $($item.Name)"
                        }
                        $editors.Add([pscustomobject]@{ name = $name; path = $item.FullName })
                    }
                }
            }
        }
        $result.candidates = @($editors | ForEach-Object { $_.name })
        if ($editors.Count -gt 1) { $result.reason_code = 'CANDIDATE_EDITOR_TARGET_AMBIGUOUS'; $result.detail = 'Multiple Editor Target.cs declarations require an explicit contract selection.' }
        elseif ($editors.Count -eq 1) {
            $result.success = $true; $result.target_name = $editors[0].name; $result.target_file = $editors[0].path
        } else {
            $modules = @(Get-ActionRoguelikeBindingProperty $Descriptor 'Modules' | Where-Object { $null -ne $_ })
            if ($modules.Count -eq 0 -and $targetFiles.Count -eq 0) {
                $result.success = $true; $result.target_name = 'UnrealEditor'; $result.build_required = $false
                $result.detail = 'The content-only project uses the installed UnrealEditor target.'
            } else { $result.reason_code = 'CANDIDATE_EDITOR_TARGET_MISSING'; $result.detail = 'A code project has no unambiguous Editor Target.cs declaration.' }
        }
        if ($result.success) { $result.attribution = $null }
    } catch { $result.reason_code = 'CANDIDATE_EDITOR_TARGET_INVALID'; $result.detail = $_.Exception.Message }
    return [pscustomobject]$result
}

function Resolve-ActionRoguelikeEngineBinding {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot, [Parameter(Mandatory)][string]$EngineRoot, [Parameter(Mandatory)]$Manifest)
    $result = [ordered]@{
        success = $false; attribution = 'host'; reason_code = $null; detail = ''
        engine_root = $null; version = $null; changelist = $null; build_version_path = $null
        editor_executable = $null; editor_cmd_executable = $null; build_tool = $null
        executor_path = $null; executor_sha256 = $null
    }
    $stage = 'manifest'
    try {
        $engine = Get-ActionRoguelikeBindingProperty $Manifest 'engine'
        $version = [string](Get-ActionRoguelikeBindingProperty $engine 'version')
        $changelist = Get-ActionRoguelikeBindingProperty $engine 'changelist'
        if ($version -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' -or $null -eq $changelist -or [string]$changelist -notmatch '^[0-9]+$') {
            throw 'The trusted manifest must declare an exact major.minor.patch engine version and integer changelist.'
        }
        $result.version = $version; $result.changelist = [long]$changelist
        $stage = 'engine'
        $root = Assert-ActionRoguelikeBindingPath -Path $EngineRoot
        $result.engine_root = $root
        $result.build_version_path = Assert-ActionRoguelikeBindingPath -Path (Join-Path $root 'Engine/Build/Build.version') -Root $root
        if (-not (Test-Path -LiteralPath $result.build_version_path -PathType Leaf)) {
            $result.reason_code = 'HOST_ENGINE_INCOMPLETE'; throw 'The supplied engine has no Engine/Build/Build.version.'
        }
        $actual = Get-Content -LiteralPath $result.build_version_path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -Depth 20 -ErrorAction Stop
        $parts = foreach ($field in @('MajorVersion', 'MinorVersion', 'PatchVersion', 'Changelist')) {
            $value = Get-ActionRoguelikeBindingProperty $actual $field
            if ($null -eq $value -or [string]$value -notmatch '^[0-9]+$') { throw "Build.version is missing an integer $field." }
            [long]$value
        }
        $actualVersion = '{0}.{1}.{2}' -f $parts[0], $parts[1], $parts[2]
        if ($actualVersion -cne $version -or $parts[3] -ne [long]$changelist) {
            $result.reason_code = 'HOST_ENGINE_IDENTITY_MISMATCH'
            throw "Engine identity is $actualVersion CL $($parts[3]); the manifest requires $version CL $changelist."
        }
        foreach ($entry in @(
            @{ key = 'editor_executable'; path = 'Engine/Binaries/Win64/UnrealEditor.exe' },
            @{ key = 'editor_cmd_executable'; path = 'Engine/Binaries/Win64/UnrealEditor-Cmd.exe' },
            @{ key = 'build_tool'; path = 'Engine/Build/BatchFiles/Build.bat' }
        )) {
            $path = Assert-ActionRoguelikeBindingPath -Path (Join-Path $root $entry.path) -Root $root
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $result.reason_code = 'HOST_ENGINE_INCOMPLETE'; throw "The supplied engine is missing $($entry.path)." }
            $result[$entry.key] = $path
        }
        $stage = 'executor'
        $repo = Assert-ActionRoguelikeBindingPath -Path $RepositoryRoot
        $expectedRelative = "engine/unreal-$version/executor/UnrealEvaluationExecutor.psm1"
        $expected = Assert-ActionRoguelikeBindingPath -Path (Join-Path $repo $expectedRelative) -Root $repo
        $tooling = Get-ActionRoguelikeBindingProperty $Manifest 'tooling'
        $identities = Get-ActionRoguelikeBindingProperty $tooling 'identities'
        $identity = Get-ActionRoguelikeBindingProperty $identities 'executor_module'
        $declared = [string](Get-ActionRoguelikeBindingProperty $identity 'path')
        if ($declared) {
            # Identity paths are repository-relative, never manifest-relative.
            if ([IO.Path]::IsPathRooted($declared) -or $declared.Contains(':')) { throw 'The declared executor identity path must be repository-relative.' }
            $declaredPath = Assert-ActionRoguelikeBindingPath -Path (Join-Path $repo $declared) -Root $repo
            if (-not $declaredPath.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) {
                $result.reason_code = 'TOOLING_EXECUTOR_VERSION_MISMATCH'; throw 'The declared executor does not belong to the exact manifest engine version.'
            }
        }
        if (-not (Test-Path -LiteralPath $expected -PathType Leaf)) {
            $result.reason_code = 'TOOLING_EXECUTOR_MISSING'; throw "The exact executor is missing: $expectedRelative"
        }
        $result.executor_path = $expected
        $result.executor_sha256 = (Get-FileHash -LiteralPath $expected -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        $declaredHash = [string](Get-ActionRoguelikeBindingProperty $identity 'sha256')
        if ($declaredHash -and ($declaredHash -notmatch '^[a-fA-F0-9]{64}$' -or $declaredHash -ine $result.executor_sha256)) {
            $result.reason_code = 'TOOLING_EXECUTOR_IDENTITY_MISMATCH'; throw 'The exact executor does not match its frozen manifest SHA-256.'
        }
        $result.success = $true; $result.attribution = $null; $result.detail = 'The engine and executor match the exact frozen manifest identity.'
    } catch {
        $result.attribution = if ($stage -eq 'engine') { 'host' } else { 'tooling' }
        if (-not $result.reason_code) { $result.reason_code = switch ($stage) { 'manifest' { 'TOOLING_MANIFEST_ENGINE_INVALID' } 'executor' { 'TOOLING_EXECUTOR_BINDING_INVALID' } default { 'HOST_ENGINE_INVALID' } } }
        $result.detail = $_.Exception.Message
    }
    return [pscustomobject]$result
}
