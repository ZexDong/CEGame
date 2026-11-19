[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [string]$UnityEditorPath=$env:UNITY_EDITOR,
    [string]$UnityCliPath=$env:UNITY_CLI,
    [string]$OutputDirectory = "",
    [switch]$RetainInvalidDiagnostics,
    [switch]$RunVisualScoring,
    [string]$VisualModel = "gpt-5.6-terra",
    [string]$VisualBaseUrl = $env:D6_BASE_URL,
    [string]$VisualApiKeyEnvironment = "D6_API_KEY",
    [switch]$AuthorCalibration,
    [ValidateSet("candidate", "gold", "input", "wrong_state_advances",
        "fixed_ui_no_persistence", "timeout_failure_hidden", "strong_equivalent")]
    [string]$CalibrationRole = "candidate"
)

$ErrorActionPreference = "Stop"
if ($AuthorCalibration) {
    throw "Private author calibration fixtures are not distributed. This release measures candidates only."
}
$evaluationRoot = Split-Path -Parent $PSScriptRoot
$demoRoot = Split-Path -Parent $evaluationRoot
$exitContractPath = Join-Path $PSScriptRoot "complete-evaluation-invocation.ps1"
. $exitContractPath
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $demoRoot "..\..")).Path.TrimEnd('\', '/')
$repoTmpRoot = (Join-Path $repoRoot "tmp").TrimEnd('\', '/')
$repoRunsRoot = (Join-Path $repoRoot "runs").TrimEnd('\', '/')
$rulesPath = Join-Path $evaluationRoot "rules.json"
$ruleSet = Get-Content -Raw -Encoding UTF8 -LiteralPath $rulesPath | ConvertFrom-Json
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$UnityEditorPath = (Resolve-Path -LiteralPath $UnityEditorPath).Path
$UnityCliPath = (Resolve-Path -LiteralPath $UnityCliPath).Path
if ($AuthorCalibration -and $CalibrationRole -eq "candidate") {
    throw "AuthorCalibration requires an explicit non-candidate CalibrationRole."
}
if (-not $AuthorCalibration -and $CalibrationRole -ne "candidate") {
    throw "A non-candidate CalibrationRole is private author calibration and requires -AuthorCalibration."
}
function Test-PathUnderRoot([string]$Path, [string]$Root) {
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    return $fullPath.StartsWith($fullRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)
}
function Assert-NoReparsePointAncestor([string]$Path, [string]$Root) {
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if (-not (Test-PathUnderRoot $fullPath $fullRoot)) {
        throw "Path must be a strict child of the repository tmp root: $fullPath"
    }
    $cursor = Split-Path -Parent $fullPath
    while (-not [string]::IsNullOrWhiteSpace($cursor)) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "OutputDirectory cannot traverse a reparse-point ancestor: $cursor"
            }
        }
        if ([string]::Equals($cursor, $fullRoot,
                [StringComparison]::OrdinalIgnoreCase)) {
            return
        }
        $parent = Split-Path -Parent $cursor
        if ([string]::Equals($parent, $cursor,
                [StringComparison]::OrdinalIgnoreCase)) {
            break
        }
        $cursor = $parent
    }
    throw "OutputDirectory ancestor walk did not reach repository tmp/: $fullPath"
}
if (-not ((Test-PathUnderRoot $ProjectPath $repoTmpRoot) -or
          (Test-PathUnderRoot $ProjectPath $repoRunsRoot))) {
    throw "ProjectPath must be a saved candidate copy under repository tmp/ or runs/; canonical demos and external paths are read-only: $ProjectPath"
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $safeName = (Split-Path -Leaf $ProjectPath) -replace '[^A-Za-z0-9._-]', '_'
    $runId = [DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss-fff")
    $OutputDirectory = Join-Path $repoTmpRoot `
        "sign-circuit-evaluation-$runId-$safeName\evaluation\raw"
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (-not (Test-PathUnderRoot $OutputDirectory $repoTmpRoot)) {
    throw "OutputDirectory must be a new path under repository tmp/. Promote the whole run to runs/ only after score.json is valid: $OutputDirectory"
}
Assert-NoReparsePointAncestor $OutputDirectory $repoTmpRoot
if (Test-PathUnderRoot $OutputDirectory $ProjectPath) {
    throw "OutputDirectory must not be inside the candidate project: $OutputDirectory"
}
if (Test-Path -LiteralPath $OutputDirectory) {
    throw "OutputDirectory must not already exist (empty or non-empty): $OutputDirectory"
}
$ownedOutputDirectory = $OutputDirectory
$outputDirectoryCreatedByThisInvocation = $false
$evidenceDirectory = Join-Path $OutputDirectory "evidence"
$scorePath = Join-Path $OutputDirectory "score.json"
$bindingPath = Join-Path $OutputDirectory "hash-binding.json"
$artifactManifestPath = Join-Path $OutputDirectory "run-artifact-manifest.json"
$strongArchitectureProofPath = Join-Path $OutputDirectory "strong-architecture-proof.json"
$evaluationSessionId = [Guid]::NewGuid().ToString("N")
$runStartedUtc = [DateTime]::UtcNow.ToString("o")
$previousTemp = $env:TEMP
$previousTmp = $env:TMP
$hostTempPath = Join-Path $repoTmpRoot "_unity-host-temp\$evaluationSessionId"
$invalidFinalReport = $null
$invalidFinalReportJson = $null
$strongSourceWitnessPaths = @(
    "Assets/Prefabs/PlayerCamera.prefab",
    "Assets/Prefabs/PlayerCamera.prefab.meta",
    "Assets/Prefabs/MainCamera.prefab",
    "Assets/Prefabs/MainCamera.prefab.meta",
    "Assets/Prefabs/CinemachineCamera.prefab",
    "Assets/Prefabs/CinemachineCamera.prefab.meta")
$strongSourceWitnessAlgorithm =
    "sha256(utf8(join(sorted(F|path|bytes|sha256), LF)))"

function Get-BytesHash([byte[]]$Bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $digest = $sha.ComputeHash($Bytes) } finally { $sha.Dispose() }
    return ([BitConverter]::ToString($digest) -replace '-', '').ToLowerInvariant()
}
function Get-StrongSourceWitnessHash([object[]]$Entries) {
    $records = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in @($Entries)) {
        $records.Add("F|$([string]$entry.path)|$([long]$entry.bytes)|$([string]$entry.sha256)")
    }
    $ordered = $records.ToArray()
    [Array]::Sort($ordered, [StringComparer]::Ordinal)
    return Get-BytesHash ([Text.Encoding]::UTF8.GetBytes(($ordered -join "`n")))
}
function Get-TreeHash([string]$BasePath, [string[]]$RelativeRoots,
    [string[]]$ExcludedRelativePaths = @()) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $excluded = @($ExcludedRelativePaths | ForEach-Object {
        ([string]$_ -replace '\\','/').TrimStart('/').TrimEnd('/')
    })
    foreach ($relativeRoot in $RelativeRoots) {
        $root = Join-Path $BasePath $relativeRoot
        if (-not (Test-Path -LiteralPath $root)) { continue }
        if (Test-Path -LiteralPath $root -PathType Leaf) {
            $files = @(Get-Item -LiteralPath $root)
        } else {
            $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force)
        }
        foreach ($file in @($files | Sort-Object FullName)) {
            $relative = $file.FullName.Substring($BasePath.Length).TrimStart('\', '/') `
                -replace '\\', '/'
            $isExcluded = $false
            foreach ($item in $excluded) {
                if ($relative -eq $item -or $relative.StartsWith(
                        $item + '/', [StringComparison]::OrdinalIgnoreCase)) {
                    $isExcluded = $true; break
                }
            }
            if ($isExcluded) { continue }
            $fileHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            $lines.Add("$relative|$fileHash")
        }
    }
    return Get-BytesHash ([System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n")))
}
function Get-CompleteTreeBinding([string]$BasePath) {
    $BasePath = (Resolve-Path -LiteralPath $BasePath).Path.TrimEnd('\', '/')
    $entries = [System.Collections.Generic.List[string]]::new()
    $fileCount = 0
    $directoryCount = 0
    foreach ($entry in @(Get-ChildItem -LiteralPath $BasePath -Recurse -Force |
            Sort-Object FullName)) {
        $relative = $entry.FullName.Substring($BasePath.Length).TrimStart('\', '/') `
            -replace '\\', '/'
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Complete-tree freeze cannot include a reparse point: $($entry.FullName)"
        }
        if ($entry.PSIsContainer) {
            $directoryCount++
            $entries.Add("D|$relative")
        } else {
            $fileCount++
            $hash = (Get-FileHash -LiteralPath $entry.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            $entries.Add("F|$relative|$($entry.Length)|$hash")
        }
    }
    return [pscustomobject]@{
        sha256 = Get-BytesHash ([Text.Encoding]::UTF8.GetBytes(($entries -join "`n")))
        file_count = $fileCount
        directory_count = $directoryCount
        entry_count = $entries.Count
    }
}
function Get-SourceFileMap([string]$BasePath) {
    $map = [System.Collections.Generic.Dictionary[string,string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($rootName in @("Assets", "Packages", "ProjectSettings")) {
        $root = Join-Path $BasePath $rootName
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File -Force)) {
            $relative = $file.FullName.Substring($BasePath.Length).TrimStart('\', '/') `
                -replace '\\', '/'
            $map[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    return $map
}
function Compare-ColdSourceProjection([string]$SourcePath, [string]$ColdPath) {
    $source = Get-SourceFileMap $SourcePath
    $cold = Get-SourceFileMap $ColdPath
    $violations = [System.Collections.Generic.List[object]]::new()
    $generatedMeta = [System.Collections.Generic.List[string]]::new()
    foreach ($path in @($source.Keys)) {
        if (-not $cold.ContainsKey($path)) {
            $violations.Add([pscustomobject]@{ kind = "missing_source_file"; path = $path })
        } elseif (-not [string]::Equals($source[$path], $cold[$path],
                [StringComparison]::OrdinalIgnoreCase)) {
            $violations.Add([pscustomobject]@{ kind = "modified_source_file"; path = $path })
        }
    }
    foreach ($path in @($cold.Keys)) {
        if ($source.ContainsKey($path)) { continue }
        $sourcePeerExists = $false
        if ($path.EndsWith(".meta", [StringComparison]::OrdinalIgnoreCase)) {
            $peerRelative = $path.Substring(0, $path.Length - 5) -replace '/', '\\'
            $sourcePeerExists = Test-Path -LiteralPath (Join-Path $SourcePath $peerRelative)
        }
        if ($sourcePeerExists -and (Test-IsAllowedCandidatePath $path)) {
            $generatedMeta.Add($path)
        } else {
            $violations.Add([pscustomobject]@{ kind = "unexpected_cold_file"; path = $path })
        }
    }
    return [pscustomobject]@{
        compliant = $violations.Count -eq 0
        source_file_count = $source.Count
        cold_file_count = $cold.Count
        unity_generated_meta = @($generatedMeta | Sort-Object)
        violations = @($violations)
    }
}
function Test-IsAllowedCandidatePath([string]$RelativePath) {
    $path = $RelativePath -replace '\\', '/'
    return $path.Equals("Assets/Benchmark.meta", [StringComparison]::OrdinalIgnoreCase) -or
        $path.StartsWith("Assets/Benchmark/", [StringComparison]::OrdinalIgnoreCase) -or
        $path.Equals("Assets/Scenes/Benchmark/SignCircuit.unity", [StringComparison]::OrdinalIgnoreCase) -or
        $path.Equals("Assets/Scenes/Menu.unity", [StringComparison]::OrdinalIgnoreCase) -or
        $path.Equals("ProjectSettings/EditorBuildSettings.asset", [StringComparison]::OrdinalIgnoreCase)
}
function Get-PublicTaskFileList {
    $manifestPath = Join-Path $demoRoot "input\BENCHMARK_MANIFEST.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Canonical Input manifest is missing: $manifestPath"
    }
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath |
        ConvertFrom-Json
    $files = @($manifest.public_task_files | ForEach-Object {
        ([string]$_ -replace '\\', '/').Trim()
    })
    if ($files.Count -eq 0) {
        throw "BENCHMARK_MANIFEST.public_task_files must not be empty."
    }
    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($relative in $files) {
        if ([string]::IsNullOrWhiteSpace($relative) -or
            [IO.Path]::IsPathRooted($relative) -or
            @($relative -split '/' | Where-Object { $_ -eq '..' }).Count -gt 0 -or
            $relative.EndsWith('/')) {
            throw "Invalid BENCHMARK_MANIFEST.public_task_files entry: '$relative'"
        }
        if (-not $seen.Add($relative)) {
            throw "Duplicate BENCHMARK_MANIFEST.public_task_files entry: '$relative'"
        }
    }
    if (-not $seen.Contains("UNITY_BENCHMARK_TOOL_GUIDE.md")) {
        throw "BENCHMARK_MANIFEST.public_task_files must bind UNITY_BENCHMARK_TOOL_GUIDE.md."
    }
    return $files
}
function Assert-ProtectedBaselineComplete([string]$BaselinePath, [bool]$IncludePublicTaskFiles) {
    foreach ($rootName in @("Assets", "Packages", "ProjectSettings")) {
        $path = Join-Path $BaselinePath $rootName
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            throw "Protected input baseline is missing required directory: $path"
        }
    }
    if ($IncludePublicTaskFiles) {
        foreach ($relative in @(Get-PublicTaskFileList)) {
            $path = Join-Path $BaselinePath $relative
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "Protected input baseline is missing required public task file: $path"
            }
        }
    }
}
function Get-ProtectedFileMap([string]$RootPath, [bool]$IncludePublicTaskFiles) {
    $map = [System.Collections.Generic.Dictionary[string,string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($rootName in @("Assets", "Packages", "ProjectSettings")) {
        $sourceRoot = Join-Path $RootPath $rootName
        if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Force)) {
            $relative = $file.FullName.Substring($RootPath.Length).TrimStart('\', '/') `
                -replace '\\', '/'
            if (Test-IsAllowedCandidatePath $relative) { continue }
            $map[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    if ($IncludePublicTaskFiles) {
        foreach ($relative in @(Get-PublicTaskFileList)) {
            $path = Join-Path $RootPath $relative
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                $map[$relative] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
    }
    return $map
}
function Get-MapHash($Map) {
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($path in @($Map.Keys | Sort-Object)) {
        $lines.Add("$path|$($Map[$path])")
    }
    return Get-BytesHash ([System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n")))
}
function Compare-ProtectedTrees(
    [string]$BaselinePath,
    [string]$CandidatePath,
    [bool]$IncludePublicTaskFiles,
    [bool]$AllowAdditionalCandidateFiles = $false) {
    $violations = [System.Collections.Generic.List[object]]::new()
    foreach ($rootName in @("Assets", "Packages", "ProjectSettings")) {
        $candidateRoot = Join-Path $CandidatePath $rootName
        if (-not (Test-Path -LiteralPath $candidateRoot -PathType Container)) {
            $violations.Add([pscustomobject]@{
                kind = "missing_required_directory"; path = $rootName
                expected_sha256 = $null; actual_sha256 = $null
            })
            continue
        }
        foreach ($entry in @(Get-ChildItem -LiteralPath $candidateRoot -Recurse -Force |
                Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 })) {
            $relative = $entry.FullName.Substring($CandidatePath.Length).TrimStart('\', '/') `
                -replace '\\', '/'
            $violations.Add([pscustomobject]@{
                kind = "reparse_point_not_allowed"; path = $relative
                expected_sha256 = $null; actual_sha256 = $null
            })
        }
    }
    $baseline = Get-ProtectedFileMap $BaselinePath $IncludePublicTaskFiles
    $candidate = Get-ProtectedFileMap $CandidatePath $IncludePublicTaskFiles
    foreach ($path in @($baseline.Keys + $candidate.Keys | Sort-Object -Unique)) {
        if (-not $baseline.ContainsKey($path)) {
            if (-not $AllowAdditionalCandidateFiles) {
                $violations.Add([pscustomobject]@{
                    kind = "unexpected_protected_file"; path = $path
                    expected_sha256 = $null; actual_sha256 = $candidate[$path]
                })
            }
        } elseif (-not $candidate.ContainsKey($path)) {
            $violations.Add([pscustomobject]@{
                kind = "missing_protected_file"; path = $path
                expected_sha256 = $baseline[$path]; actual_sha256 = $null
            })
        } elseif (-not [string]::Equals($baseline[$path], $candidate[$path],
                [StringComparison]::OrdinalIgnoreCase)) {
            $violations.Add([pscustomobject]@{
                kind = "modified_protected_file"; path = $path
                expected_sha256 = $baseline[$path]; actual_sha256 = $candidate[$path]
            })
        }
    }
    return [pscustomobject]@{
        compliant = $violations.Count -eq 0
        baseline_file_count = $baseline.Count
        candidate_file_count = $candidate.Count
        baseline_sha256 = Get-MapHash $baseline
        candidate_sha256 = Get-MapHash $candidate
        violations = @($violations)
    }
}
function Remove-TreeRobust([string]$Path, [string]$AllowedParent) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $resolved = [IO.Path]::GetFullPath($Path)
    $parent = [IO.Path]::GetFullPath($AllowedParent).TrimEnd('\', '/')
    $prefix = $parent + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete path outside the evaluation output: $resolved"
    }
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            Get-ChildItem -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue |
                ForEach-Object {
                    try { $_.Attributes = [IO.FileAttributes]::Normal } catch { }
                }
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
        } catch {
            if ($attempt -eq 5) {
                try {
                    $longPath = if ($resolved.StartsWith('\\?\')) { $resolved } else { '\\?\' + $resolved }
                    [IO.Directory]::Delete($longPath, $true)
                } catch {
                    throw "Failed to remove evaluation scratch tree '$resolved': $($_.Exception.Message)"
                }
            } else {
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
                Start-Sleep -Milliseconds (150 * $attempt)
            }
        }
        if (-not (Test-Path -LiteralPath $resolved)) { return }
    }
    if (Test-Path -LiteralPath $resolved) {
        throw "Evaluation scratch tree still exists after cleanup: $resolved"
    }
}
function Assert-ExactOwnedOutputPath(
    [string]$Path,
    [string]$ExpectedOwnedPath,
    [string]$RepositoryTmpRoot
) {
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $fullExpected = [IO.Path]::GetFullPath($ExpectedOwnedPath).TrimEnd('\', '/')
    $fullTmpRoot = [IO.Path]::GetFullPath($RepositoryTmpRoot).TrimEnd('\', '/')
    if (-not [string]::Equals($fullPath, $fullExpected,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing invalid-output cleanup for a path other than this invocation's exact OutputDirectory: $fullPath"
    }
    if (-not (Test-PathUnderRoot $fullPath $fullTmpRoot)) {
        throw "Refusing invalid-output cleanup or retention outside repository tmp/: $fullPath"
    }
    Assert-NoReparsePointAncestor $fullPath $fullTmpRoot
}
function Remove-FileSystemTreeWithoutFollowingReparsePoints([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    $isReparsePoint =
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    $isDirectory =
        ($item.Attributes -band [IO.FileAttributes]::Directory) -ne 0
    if ($isReparsePoint) {
        if ($isDirectory) {
            [IO.Directory]::Delete($item.FullName, $false)
        } else {
            [IO.File]::Delete($item.FullName)
        }
        return
    }
    if (-not $isDirectory) {
        try { $item.Attributes = [IO.FileAttributes]::Normal } catch { }
        [IO.File]::Delete($item.FullName)
        return
    }
    foreach ($child in @([IO.DirectoryInfo]::new($item.FullName).GetFileSystemInfos())) {
        Remove-FileSystemTreeWithoutFollowingReparsePoints $child.FullName
    }
    try { $item.Attributes = [IO.FileAttributes]::Directory } catch { }
    [IO.Directory]::Delete($item.FullName, $false)
}
function Remove-InvalidOutputDirectory(
    [string]$Path,
    [string]$ExpectedOwnedPath,
    [string]$RepositoryTmpRoot
) {
    Assert-ExactOwnedOutputPath $Path $ExpectedOwnedPath $RepositoryTmpRoot
    if (-not (Test-Path -LiteralPath $Path)) { return }
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            Remove-FileSystemTreeWithoutFollowingReparsePoints $Path
        } catch {
            if ($attempt -eq 5) {
                throw "Failed to remove this invocation's exact invalid OutputDirectory '$Path': $($_.Exception.Message)"
            }
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            Start-Sleep -Milliseconds (150 * $attempt)
        }
        if (-not (Test-Path -LiteralPath $Path)) { return }
    }
    if (Test-Path -LiteralPath $Path) {
        throw "This invocation's exact invalid OutputDirectory still exists after cleanup: $Path"
    }
}
function Write-InvalidDiagnosticMarker(
    [string]$Path,
    [string]$ExpectedOwnedPath,
    [string]$RepositoryTmpRoot,
    [string]$ReasonKind,
    [object]$InvalidReport,
    [string]$SessionId,
    [string]$CandidateProjectPath,
    [string]$ExceptionMessage = "",
    [string]$DiagnosticScoreWriteFailure = ""
) {
    Assert-ExactOwnedOutputPath $Path $ExpectedOwnedPath $RepositoryTmpRoot
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Cannot retain invalid diagnostics because OutputDirectory is absent: $Path"
    }
    $manifestPath = Join-Path $Path "run-artifact-manifest.json"
    if (Test-Path -LiteralPath $manifestPath) {
        Remove-FileSystemTreeWithoutFollowingReparsePoints $manifestPath
    }
    if (Test-Path -LiteralPath $manifestPath) {
        throw "Invalid diagnostics cannot retain a formal artifact manifest: $manifestPath"
    }
    $scorePresent = Test-Path -LiteralPath (Join-Path $Path "score.json") -PathType Leaf
    $marker = [pscustomobject][ordered]@{
        schema_version = 1
        kind = "author_diagnostic_invalid_run"
        generated_utc = [DateTime]::UtcNow.ToString("o")
        evaluation_session_id = $SessionId
        reason_kind = $ReasonKind
        valid_score = $false
        formal_result = $false
        eligible_for_promotion = $false
        must_not_be_reported_as_score = $true
        retained_by_explicit_switch = $true
        output_directory = [IO.Path]::GetFullPath($Path)
        project_path = $CandidateProjectPath
        score_json_present = [bool]$scorePresent
        invalid_report_valid_score = if ($null -eq $InvalidReport) {
            $false
        } else {
            [bool]$InvalidReport.valid_score
        }
        exception_message = if ([string]::IsNullOrWhiteSpace($ExceptionMessage)) {
            $null
        } else { $ExceptionMessage }
        diagnostic_score_write_failure = if ([string]::IsNullOrWhiteSpace(
                $DiagnosticScoreWriteFailure)) {
            $null
        } else { $DiagnosticScoreWriteFailure }
        formal_manifest_removed = -not (Test-Path -LiteralPath $manifestPath)
    }
    $markerPath = Join-Path $Path "AUTHOR_DIAGNOSTIC_INVALID.json"
    if (Test-Path -LiteralPath $markerPath) {
        Remove-FileSystemTreeWithoutFollowingReparsePoints $markerPath
    }
    [IO.File]::WriteAllText($markerPath,
        ($marker | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    return $marker
}
function Complete-InvalidEvaluationOutput(
    [string]$Path,
    [string]$ExpectedOwnedPath,
    [string]$RepositoryTmpRoot,
    [string]$ReasonKind,
    [object]$InvalidReport,
    [string]$SessionId,
    [string]$CandidateProjectPath,
    [switch]$Retain,
    [string]$ExceptionMessage = "",
    [string]$DiagnosticScoreWriteFailure = ""
) {
    Assert-ExactOwnedOutputPath $Path $ExpectedOwnedPath $RepositoryTmpRoot
    if (-not (Test-Path -LiteralPath $Path)) { return "already_absent" }
    if ($Retain) {
        $null = Write-InvalidDiagnosticMarker `
            $Path $ExpectedOwnedPath $RepositoryTmpRoot $ReasonKind `
            $InvalidReport $SessionId $CandidateProjectPath $ExceptionMessage `
            $DiagnosticScoreWriteFailure
        return "retained_author_diagnostic"
    }
    Remove-InvalidOutputDirectory $Path $ExpectedOwnedPath $RepositoryTmpRoot
    return "deleted"
}
function Remove-IsolatedUnityPersistence([string]$Company, [string]$Product) {
    if ($Company -ne "OmniGameSignCircuitEvaluator" -or
        $Product -notmatch '^SignCircuit_[0-9a-f]{32}$') {
        throw "Refusing to clean an unexpected Unity persistence identity: $Company/$Product"
    }

    $localAppData = [Environment]::GetFolderPath(
        [Environment+SpecialFolder]::LocalApplicationData)
    $localLow = Join-Path (Split-Path -Parent $localAppData) "LocalLow"
    $companyRoot = Join-Path $localLow $Company
    $persistentPath = Join-Path $companyRoot $Product
    if (Test-Path -LiteralPath $persistentPath) {
        Remove-TreeRobust $persistentPath $companyRoot
    }
    if ((Test-Path -LiteralPath $companyRoot -PathType Container) -and
        @(Get-ChildItem -LiteralPath $companyRoot -Force).Count -eq 0) {
        Remove-Item -LiteralPath $companyRoot -Force
    }

    $registryProductPath = "Software\Unity\UnityEditor\$Company\$Product"
    $registryCompanyPath = "Software\Unity\UnityEditor\$Company"
    $currentUser = [Microsoft.Win32.Registry]::CurrentUser
    $currentUser.DeleteSubKeyTree($registryProductPath, $false)
    $companyKey = $currentUser.OpenSubKey($registryCompanyPath, $true)
    if ($null -ne $companyKey) {
        try {
            $companyEmpty = $companyKey.SubKeyCount -eq 0 -and
                $companyKey.ValueCount -eq 0
        } finally {
            $companyKey.Dispose()
        }
        if ($companyEmpty) {
            $currentUser.DeleteSubKey($registryCompanyPath, $false)
        }
    }

    $remainingRegistryKey = $currentUser.OpenSubKey($registryProductPath, $false)
    $registryAbsent = $null -eq $remainingRegistryKey
    if ($null -ne $remainingRegistryKey) {
        $remainingRegistryKey.Dispose()
    }

    return [pscustomobject]@{
        company = $Company
        product = $Product
        persistent_data_path = $persistentPath
        player_prefs_registry_path = $registryProductPath
        persistent_path_absent_after_cleanup =
            -not (Test-Path -LiteralPath $persistentPath)
        registry_key_absent_after_cleanup = $registryAbsent
    }
}
function Invoke-JsonScript([string]$Path, [hashtable]$Parameters) {
    $raw = & $Path @Parameters
    return (($raw -join [Environment]::NewLine) | ConvertFrom-Json)
}
function Clear-PhaseEvidence([string]$Phase) {
    if (-not (Test-PathUnderRoot $evidenceDirectory $OutputDirectory)) {
        throw "Refusing to clear evidence outside this evaluation output: $evidenceDirectory"
    }
    $declared = @($ruleSet.phases.$($Phase.ToLowerInvariant()).tests |
        ForEach-Object { [string]$_.id })
    foreach ($id in $declared) {
        $path = Join-Path $evidenceDirectory (($id -replace '[^A-Za-z0-9._-]', '_') + '.json')
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Remove-Item -LiteralPath $path -Force
        }
    }
    if ($Phase -eq 'Dynamic') {
        $seed = Join-Path $evidenceDirectory 'fresh-seed.json'
        if (Test-Path -LiteralPath $seed -PathType Leaf) {
            Remove-Item -LiteralPath $seed -Force
        }
        foreach ($capture in @(Get-ChildItem -LiteralPath $evidenceDirectory `
                -File -Filter 'visual-*.png' -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $capture.FullName -Force
        }
    }
}
function New-UnevaluatedDimensions([Nullable[double]]$D1Score = $null,
    [string]$Status = "not_evaluated") {
    $items = [ordered]@{}
    foreach ($entry in @(
        @("D1", 10), @("D2", 30), @("D3", 20),
        @("D4", 20), @("D5", 10), @("D6", 10))) {
        $id = [string]$entry[0]
        $score = if ($id -eq "D1") { $D1Score } else { $null }
        $items[$id] = [pscustomobject]@{
            score = $score
            maximum_score = [double]$entry[1]
            status = if ($id -eq "D6") { "pending" } else { $Status }
        }
    }
    return [pscustomobject]$items
}
function Assert-PhaseUsable($Run) {
    if ([string]$Run.execution_status -eq "infrastructure_error") {
        throw "$($Run.phase) infrastructure failure. See $($Run.log)"
    }
    if (-not (Test-Path -LiteralPath ([string]$Run.result) -PathType Leaf)) {
        if ([string]$Run.failure_kind -eq "candidate_compilation_error" -and
            @($Run.compiler_errors).Count -gt 0) {
            throw "$($Run.phase) exposed candidate compiler errors after evaluator injection. See $($Run.log)"
        }
        throw "$($Run.phase) produced no NUnit XML. See $($Run.log)"
    }
}
function Get-UnityProcessIdFromPhaseReceipt($Run, [string]$PhaseName) {
    if ($null -eq $Run -or
        $null -eq $Run.PSObject.Properties['unity_process_id']) {
        throw "$PhaseName phase receipt is missing unity_process_id."
    }
    try { $processId = [int]$Run.unity_process_id }
    catch { $processId = 0 }
    if ($processId -le 0) {
        throw "$PhaseName phase receipt has no positive actual Unity PID."
    }
    return $processId
}
function Test-StaticFullPass([string]$ResultPath) {
    [xml]$xml = Get-Content -Raw -Encoding UTF8 -LiteralPath $ResultPath
    $rules = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $evaluationRoot "rules.json") |
        ConvertFrom-Json
    foreach ($rule in @($rules.phases.static.tests)) {
        $matches = @($xml.SelectNodes("//test-case") | Where-Object {
            [string]$_.methodname -eq [string]$rule.id -or
            [string]$_.name -eq [string]$rule.id
        })
        if ($matches.Count -ne 1 -or [string]$matches[0].result -ne "Passed") {
            return $false
        }
    }
    return $true
}
function Get-StaticFailureClassification([string]$ResultPath) {
    [xml]$xml = Get-Content -Raw -Encoding UTF8 -LiteralPath $ResultPath
    $rules = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $evaluationRoot "rules.json") |
        ConvertFrom-Json
    $candidateMarker = "[OMNIGAME_SIGN_CIRCUIT_CANDIDATE_STATIC]"
    $messages = [System.Collections.Generic.List[string]]::new()
    $hasCandidateFailure = $false
    foreach ($rule in @($rules.phases.static.tests)) {
        $matches = @($xml.SelectNodes("//test-case") | Where-Object {
            [string]$_.methodname -eq [string]$rule.id -or
            [string]$_.name -eq [string]$rule.id
        })
        if ($matches.Count -ne 1) {
            $messages.Add("Expected one $($rule.id), found $($matches.Count).")
            continue
        }
        $case = $matches[0]
        if ([string]$case.result -eq "Passed") { continue }
        $messageNode = $case.SelectSingleNode("failure/message")
        if ($null -eq $messageNode) {
            $messageNode = $case.SelectSingleNode("reason/message")
        }
        $message = if ($null -eq $messageNode) {
            "$($rule.id) returned $([string]$case.result) without a failure message."
        } else {
            ([string]$messageNode.InnerText).Trim()
        }
        if ($message.IndexOf($candidateMarker, [StringComparison]::Ordinal) -ge 0) {
            $hasCandidateFailure = $true
        } else {
            $messages.Add("$($rule.id): $message")
        }
    }
    return [pscustomobject]@{
        has_candidate_failure = $hasCandidateFailure
        non_candidate_failures = @($messages)
    }
}

function Get-RunRelativePath([string]$Path) {
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $root = $OutputDirectory.TrimEnd('\', '/')
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Run artifact is outside OutputDirectory: $resolved"
    }
    return ($resolved.Substring($prefix.Length) -replace '\\', '/')
}

function Get-DetailedProjectTreeBinding([string]$BasePath,
    [string[]]$ExcludedRelativePaths = @()) {
    $BasePath = (Resolve-Path -LiteralPath $BasePath).Path.TrimEnd('\', '/')
    $excluded = @($ExcludedRelativePaths | ForEach-Object {
        ([string]$_ -replace '\\','/').TrimStart('/').TrimEnd('/')
    })
    $recordMap = [Collections.Generic.Dictionary[string,object]]::new(
        [StringComparer]::Ordinal)
    [long]$byteCount = 0
    $fileCount = 0
    $directoryCount = 0
    foreach ($rootName in @("Assets", "Packages", "ProjectSettings")) {
        $root = Join-Path $BasePath $rootName
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            throw "Detailed project tree is missing required directory: $root"
        }
        $items = @()
        $items += Get-Item -LiteralPath $root
        $items += @(Get-ChildItem -LiteralPath $root -Recurse -Force)
        foreach ($item in @($items | Sort-Object FullName)) {
            $relative = $item.FullName.Substring($BasePath.Length).TrimStart('\', '/') `
                -replace '\\', '/'
            $isExcluded = $false
            foreach ($path in $excluded) {
                if ($relative -eq $path -or $relative.StartsWith(
                        $path + '/', [StringComparison]::OrdinalIgnoreCase)) {
                    $isExcluded = $true
                    break
                }
            }
            if ($isExcluded) { continue }
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Detailed project tree cannot contain a reparse point: $($item.FullName)"
            }
            if ($item.PSIsContainer) {
                $directoryCount++
                $record = "D|$relative"
                $recordMap[$record] = [pscustomobject]@{
                    type = "directory"; path = $relative
                }
            }
            else {
                $fileCount++
                $byteCount += [long]$item.Length
                $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                $record = "F|$relative|$($item.Length)|$hash"
                $recordMap[$record] = [pscustomobject]@{
                    type = "file"; path = $relative
                    bytes = [long]$item.Length; sha256 = $hash
                }
            }
        }
    }
    [string[]]$ordered = @($recordMap.Keys)
    [Array]::Sort($ordered, [StringComparer]::Ordinal)
    return [pscustomobject]@{
        schema_version = 1
        algorithm = "sha256(utf8(join(sorted(D|path or F|path|bytes|sha256), LF)))"
        sha256 = Get-BytesHash ([Text.UTF8Encoding]::new($false).GetBytes(
                ($ordered -join "`n")))
        file_count = $fileCount
        directory_count = $directoryCount
        byte_count = $byteCount
        entry_count = $ordered.Count
        excluded_relative_paths = @($excluded)
        entries = @($ordered | ForEach-Object { $recordMap[$_] })
    }
}

function Get-DetailedTreeSummary($Tree) {
    return [pscustomobject]@{
        schema_version = [int]$Tree.schema_version
        algorithm = [string]$Tree.algorithm
        sha256 = [string]$Tree.sha256
        file_count = [int]$Tree.file_count
        directory_count = [int]$Tree.directory_count
        byte_count = [long]$Tree.byte_count
        entry_count = [int]$Tree.entry_count
        excluded_relative_paths = @($Tree.excluded_relative_paths)
    }
}

function Test-DetailedTreeEqual($Left, $Right) {
    foreach ($property in @("schema_version", "algorithm", "sha256", "file_count",
            "directory_count", "byte_count", "entry_count")) {
        if ([string]$Left.$property -cne [string]$Right.$property) { return $false }
    }
    [string[]]$leftExcluded = @(
        @($Left.excluded_relative_paths) | Where-Object { $null -ne $_ } |
            ForEach-Object { [string]$_ } | Sort-Object)
    [string[]]$rightExcluded = @(
        @($Right.excluded_relative_paths) | Where-Object { $null -ne $_ } |
            ForEach-Object { [string]$_ } | Sort-Object)
    if ($leftExcluded.Count -eq 0 -and $rightExcluded.Count -eq 0) { return $true }
    return @(Compare-Object -ReferenceObject $leftExcluded `
        -DifferenceObject $rightExcluded -CaseSensitive).Count -eq 0
}

function Get-ProjectInventory([string]$BasePath, [string]$Label,
    [string[]]$ExcludedRelativePaths = @()) {
    $BasePath = (Resolve-Path -LiteralPath $BasePath).Path.TrimEnd('\', '/')
    $gameplayTree = Get-DetailedProjectTreeBinding $BasePath $ExcludedRelativePaths
    $entries = [System.Collections.Generic.List[object]]::new()
    $byteCount = [long]0
    $excluded = @($ExcludedRelativePaths | ForEach-Object {
        ([string]$_ -replace '\\','/').TrimStart('/').TrimEnd('/')
    })
    foreach ($rootName in @("Assets", "Packages", "ProjectSettings")) {
        $root = Join-Path $BasePath $rootName
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            throw "Project inventory is missing required directory: $root"
        }
        foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File -Force |
                Sort-Object FullName)) {
            if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Project inventory cannot contain a reparse point: $($file.FullName)"
            }
            $relative = $file.FullName.Substring($BasePath.Length).TrimStart('\', '/') `
                -replace '\\', '/'
            $isExcluded = $false
            foreach ($item in $excluded) {
                if ($relative -eq $item -or $relative.StartsWith(
                        $item + '/', [StringComparison]::OrdinalIgnoreCase)) {
                    $isExcluded = $true; break
                }
            }
            if ($isExcluded) { continue }
            $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            $byteCount += [long]$file.Length
            $entries.Add([pscustomobject]@{
                path = $relative
                bytes = [long]$file.Length
                sha256 = $hash
            })
        }
    }
    return [pscustomobject]@{
        schema_version = 1
        label = $Label
        project_tree_sha256 = Get-TreeHash $BasePath `
            @("Assets", "Packages", "ProjectSettings") $ExcludedRelativePaths
        file_count = $entries.Count
        byte_count = $byteCount
        excluded_relative_paths = @($excluded)
        entries = @($entries)
        gameplay_tree = $gameplayTree
    }
}

function Write-SourceProof([string]$SourcePath, [string]$BaselinePath,
    [string]$Role, [string[]]$ExcludedRelativePaths = @()) {
    $proofRoot = Join-Path $OutputDirectory "source-proof"
    New-Item -ItemType Directory -Path $proofRoot | Out-Null
    $candidateInventory = Get-ProjectInventory `
        $SourcePath "candidate-source" $ExcludedRelativePaths
    $baselineInventory = Get-ProjectInventory $BaselinePath "comparison-baseline"
    $candidateInventory | Add-Member -MemberType NoteProperty `
        -Name evaluation_session_id -Value $evaluationSessionId -Force
    $candidateInventory | Add-Member -MemberType NoteProperty `
        -Name calibration_role -Value $Role -Force
    $candidateInventoryPath = Join-Path $proofRoot "candidate-inventory.json"
    [IO.File]::WriteAllText($candidateInventoryPath,
        ($candidateInventory | ConvertTo-Json -Depth 12),
        [Text.UTF8Encoding]::new($false))

    $candidateMap = @{}
    foreach ($entry in @($candidateInventory.entries)) {
        $candidateMap[[string]$entry.path] = $entry
    }
    $baselineMap = @{}
    foreach ($entry in @($baselineInventory.entries)) {
        $baselineMap[[string]$entry.path] = $entry
    }
    $deltaEntries = [System.Collections.Generic.List[object]]::new()
    $allPaths = @($candidateMap.Keys + $baselineMap.Keys | Sort-Object -Unique)
    foreach ($relative in $allPaths) {
        $candidateEntry = $candidateMap[$relative]
        $baselineEntry = $baselineMap[$relative]
        $status = if ($null -eq $baselineEntry) {
            "added"
        } elseif ($null -eq $candidateEntry) {
            "deleted"
        } elseif (-not [string]::Equals([string]$candidateEntry.sha256,
                [string]$baselineEntry.sha256, [StringComparison]::OrdinalIgnoreCase)) {
            "modified"
        } else { "unchanged" }
        if ($status -eq "unchanged") { continue }
        $snapshotPath = $null
        if ($status -ne "deleted") {
            $sourceFile = Join-Path $SourcePath ($relative -replace '/', '\')
            $snapshotFile = Join-Path $proofRoot ("candidate\" + ($relative -replace '/', '\'))
            New-Item -ItemType Directory -Path (Split-Path -Parent $snapshotFile) -Force |
                Out-Null
            Copy-Item -LiteralPath $sourceFile -Destination $snapshotFile -Force
            $snapshotPath = Get-RunRelativePath $snapshotFile
        }
        $deltaEntries.Add([pscustomobject]@{
            path = $relative
            status = $status
            baseline_sha256 = if ($null -eq $baselineEntry) { $null } else {
                [string]$baselineEntry.sha256
            }
            candidate_sha256 = if ($null -eq $candidateEntry) { $null } else {
                [string]$candidateEntry.sha256
            }
            candidate_bytes = if ($null -eq $candidateEntry) { $null } else {
                [long]$candidateEntry.bytes
            }
            snapshot_path = $snapshotPath
        })
    }
    if ($Role -in @("gold", "input") -and $deltaEntries.Count -ne 0) {
        throw "$Role calibration source differs from its canonical comparison baseline."
    }
    if ($Role -in @("wrong_state_advances", "fixed_ui_no_persistence",
            "timeout_failure_hidden", "strong_equivalent") -and
        $deltaEntries.Count -eq 0) {
        throw "$Role calibration source has no source delta from canonical Gold."
    }
    $witnessInventory = $null
    $witnessInventoryPath = $null
    if ($Role -eq "strong_equivalent") {
        $witnessEntries = [System.Collections.Generic.List[object]]::new()
        [long]$witnessBytes = 0
        foreach ($relative in @($strongSourceWitnessPaths | Sort-Object)) {
            $candidateEntry = $candidateMap[$relative]
            $baselineEntry = $baselineMap[$relative]
            if ($null -eq $candidateEntry -or $null -eq $baselineEntry) {
                throw "Strong source witness is missing from candidate or canonical Gold: $relative"
            }
            if ([string]$candidateEntry.sha256 -cne [string]$baselineEntry.sha256 -or
                [long]$candidateEntry.bytes -ne [long]$baselineEntry.bytes) {
                throw "Strong source witness is not byte-identical to canonical Gold: $relative"
            }
            $sourceFile = Join-Path $SourcePath ($relative -replace '/', '\')
            $snapshotFile = Join-Path $proofRoot `
                ("strong-replay-witness\" + ($relative -replace '/', '\'))
            New-Item -ItemType Directory -Path (Split-Path -Parent $snapshotFile) -Force |
                Out-Null
            Copy-Item -LiteralPath $sourceFile -Destination $snapshotFile -Force
            $witnessBytes += [long]$candidateEntry.bytes
            $witnessEntries.Add([pscustomobject][ordered]@{
                path = $relative
                bytes = [long]$candidateEntry.bytes
                sha256 = [string]$candidateEntry.sha256
                snapshot_path = Get-RunRelativePath $snapshotFile
            })
        }
        $witnessInventory = [pscustomobject][ordered]@{
            schema_version = 1
            algorithm = $strongSourceWitnessAlgorithm
            evaluation_session_id = $evaluationSessionId
            calibration_role = $Role
            candidate_project_tree_sha256 = [string]$candidateInventory.project_tree_sha256
            baseline_project_tree_sha256 = [string]$baselineInventory.project_tree_sha256
            inventory_sha256 = Get-StrongSourceWitnessHash @($witnessEntries)
            file_count = $witnessEntries.Count
            byte_count = $witnessBytes
            entries = @($witnessEntries)
        }
        $witnessInventoryPath = Join-Path $proofRoot "strong-replay-witness.json"
        [IO.File]::WriteAllText($witnessInventoryPath,
            ($witnessInventory | ConvertTo-Json -Depth 12),
            [Text.UTF8Encoding]::new($false))
    }
    $delta = [pscustomobject]@{
        schema_version = 1
        evaluation_session_id = $evaluationSessionId
        calibration_role = $Role
        baseline_label = if ($Role -in @("candidate", "input")) {
            "canonical-input"
        } else { "canonical-gold" }
        baseline_project_tree_sha256 = $baselineInventory.project_tree_sha256
        candidate_project_tree_sha256 = $candidateInventory.project_tree_sha256
        delta_count = $deltaEntries.Count
        entries = @($deltaEntries)
    }
    $deltaPath = Join-Path $proofRoot "delta.json"
    [IO.File]::WriteAllText($deltaPath, ($delta | ConvertTo-Json -Depth 12),
        [Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{
        root = $proofRoot
        candidate_inventory_path = $candidateInventoryPath
        delta_path = $deltaPath
        candidate_inventory = $candidateInventory
        delta = $delta
        witness_inventory_path = $witnessInventoryPath
        witness_inventory = $witnessInventory
        witness_root = if ($null -eq $witnessInventory) { $null } else {
            Join-Path $proofRoot "strong-replay-witness"
        }
    }
}

function Get-CalibrationProofExclusions([string]$Role) {
    if ($Role -in @("wrong_state_advances", "fixed_ui_no_persistence",
            "timeout_failure_hidden")) {
        return @(
            "Assets/Benchmark/MutantProvenance.json",
            "Assets/Benchmark/MutantProvenance.json.meta")
    }
    if ($Role -eq "strong_equivalent") {
        return @(
            "Assets/Benchmark/StrongEquivalentProvenance.json",
            "Assets/Benchmark/StrongEquivalentProvenance.json.meta",
            "Assets/Benchmark/Provenance",
            "Assets/Benchmark/Provenance.meta")
    }
    return @()
}

function Write-MaterializationProof([string]$SourcePath, [string]$Role,
    [string[]]$ExcludedRelativePaths) {
    if ($ExcludedRelativePaths.Count -eq 0) { return $null }
    $proofRoot = Join-Path $OutputDirectory "materialization-proof"
    New-Item -ItemType Directory -Path $proofRoot | Out-Null
    $copied = [System.Collections.Generic.List[string]]::new()
    foreach ($relative in $ExcludedRelativePaths) {
        $source = Join-Path $SourcePath ($relative -replace '/', '\')
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            $files = @(Get-Item -LiteralPath $source)
        } elseif (Test-Path -LiteralPath $source -PathType Container) {
            $files = @(Get-ChildItem -LiteralPath $source -Recurse -File -Force)
        } else { continue }
        foreach ($file in $files) {
            $projectRelative = $file.FullName.Substring($SourcePath.Length).TrimStart('\', '/') `
                -replace '\\', '/'
            $destination = Join-Path $proofRoot ($projectRelative -replace '/', '\')
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force |
                Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
            $copied.Add($projectRelative)
        }
    }
    $receiptRelative = if ($Role -eq "strong_equivalent") {
        "Assets/Benchmark/StrongEquivalentProvenance.json"
    } else { "Assets/Benchmark/MutantProvenance.json" }
    $receiptPath = Join-Path $proofRoot ($receiptRelative -replace '/', '\')
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        throw "$Role materialization receipt is missing from the candidate source."
    }
    return [pscustomobject]@{
        root = $proofRoot
        receipt_path = $receiptPath
        copied_relative_paths = @($copied | Sort-Object -Unique)
        excluded_relative_paths = @($ExcludedRelativePaths)
    }
}

function New-FileArtifact([string]$Role, [string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or
        -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $item = Get-Item -LiteralPath $Path
    return [pscustomobject]@{
        role = $Role
        kind = "file"
        path = Get-RunRelativePath $item.FullName
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        bytes = [long]$item.Length
    }
}

function New-TreeArtifact([string]$Role, [string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or
        -not (Test-Path -LiteralPath $Path -PathType Container)) { return $null }
    $binding = Get-CompleteTreeBinding $Path
    $bytes = (@(Get-ChildItem -LiteralPath $Path -Recurse -File -Force) |
        Measure-Object -Property Length -Sum).Sum
    if ($null -eq $bytes) { $bytes = 0 }
    return [pscustomobject]@{
        role = $Role
        kind = "tree"
        path = Get-RunRelativePath $Path
        sha256 = [string]$binding.sha256
        bytes = [long]$bytes
        file_count = [int]$binding.file_count
        directory_count = [int]$binding.directory_count
        entry_count = [int]$binding.entry_count
    }
}

function Get-NUnitReceipt([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or
        -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    [xml]$xml = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path
    $tests = [System.Collections.Generic.List[object]]::new()
    foreach ($case in @($xml.SelectNodes("//test-case") | Sort-Object {
                if ([string]::IsNullOrWhiteSpace([string]$_.methodname)) {
                    [string]$_.name
                } else { [string]$_.methodname }
            })) {
        $tests.Add([pscustomobject]@{
            id = if ([string]::IsNullOrWhiteSpace([string]$case.methodname)) {
                [string]$case.name
            } else { [string]$case.methodname }
            result = [string]$case.result
            duration = [string]$case.duration
            asserts = [string]$case.asserts
        })
    }
    return [pscustomobject]@{ test_count = $tests.Count; tests = @($tests) }
}

function Get-PhaseReceipt($Run, [string]$PhaseName) {
    if ($null -eq $Run) { return $null }
    $resultPath = if ($null -eq $Run.PSObject.Properties["result"]) { $null } else {
        [string]$Run.result
    }
    $logPath = if ($null -eq $Run.PSObject.Properties["log"]) { $null } else {
        [string]$Run.log
    }
    $stdoutPath = if ($null -eq $Run.PSObject.Properties["cli_stdout_log"]) {
        $null
    } else { [string]$Run.cli_stdout_log }
    $stderrPath = if ($null -eq $Run.PSObject.Properties["stderr_log"]) {
        $null
    } else { [string]$Run.stderr_log }
    return [pscustomobject]@{
        phase = $PhaseName
        evaluation_session_id = [string]$Run.evaluation_session_id
        phase_run_id = [string]$Run.phase_run_id
        started_utc = [string]$Run.started_utc
        completed_utc = [string]$Run.completed_utc
        unity_process_id = $Run.unity_process_id
        cli_process_id = $Run.cli_process_id
        timeout_seconds = $Run.timeout_seconds
        executor = if ($null -eq $Run.PSObject.Properties["executor"]) {
            $null
        } else { [string]$Run.executor }
        exit_code = $Run.exit_code
        execution_status = [string]$Run.execution_status
        failure_kind = [string]$Run.failure_kind
        result_path = if ($null -eq $resultPath -or
            -not (Test-Path -LiteralPath $resultPath -PathType Leaf)) { $null } else {
            Get-RunRelativePath $resultPath
        }
        log_path = if ($null -eq $logPath -or
            -not (Test-Path -LiteralPath $logPath -PathType Leaf)) { $null } else {
            Get-RunRelativePath $logPath
        }
        cli_stdout_log_path = if ($null -eq $stdoutPath -or
            -not (Test-Path -LiteralPath $stdoutPath -PathType Leaf)) { $null } else {
            Get-RunRelativePath $stdoutPath
        }
        stderr_log_path = if ($null -eq $stderrPath -or
            -not (Test-Path -LiteralPath $stderrPath -PathType Leaf)) { $null } else {
            Get-RunRelativePath $stderrPath
        }
        nunit = Get-NUnitReceipt $resultPath
    }
}

function Get-SealedRunFiles {
    $files = [System.Collections.Generic.List[object]]::new()
    $sealableFiles = [System.Collections.Generic.List[IO.FileInfo]]::new()
    $totalBytes = [long]0
    foreach ($entry in @(Get-ChildItem -LiteralPath $OutputDirectory -Force |
            Sort-Object FullName)) {
        if ($entry.Name -in @("_candidate-cold", "_private-evaluator-package")) {
            continue
        }
        if ($entry.PSIsContainer) {
            foreach ($file in @(Get-ChildItem -LiteralPath $entry.FullName `
                    -Recurse -File -Force)) {
                $sealableFiles.Add($file)
            }
        } elseif ($entry.Name -cne "run-artifact-manifest.json") {
            $sealableFiles.Add($entry)
        }
    }
    foreach ($file in @($sealableFiles | Sort-Object FullName)) {
        $relative = Get-RunRelativePath $file.FullName
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $totalBytes += [long]$file.Length
        $files.Add([pscustomobject]@{
            path = $relative
            bytes = [long]$file.Length
            sha256 = $hash
        })
    }
    $lines = @($files | ForEach-Object { "F|$($_.path)|$($_.bytes)|$($_.sha256)" })
    return [pscustomobject]@{
        sha256 = Get-BytesHash ([Text.Encoding]::UTF8.GetBytes(($lines -join "`n")))
        file_count = $files.Count
        byte_count = $totalBytes
        files = @($files)
    }
}

function Write-RunArtifactManifest($Baseline, $Static, $Dynamic, $Fresh,
    $SourceProof, $MaterializationProof) {
    if (-not (Test-Path -LiteralPath $scorePath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $bindingPath -PathType Leaf)) {
        throw "A completed run manifest requires score.json and hash-binding.json."
    }
    $score = Get-Content -Raw -Encoding UTF8 -LiteralPath $scorePath | ConvertFrom-Json
    $binding = Get-Content -Raw -Encoding UTF8 -LiteralPath $bindingPath | ConvertFrom-Json
    if (-not [bool]$score.valid_score) {
        throw "Refusing to seal or promote an invalid score as a completed run artifact manifest."
    }
    $artifacts = [System.Collections.Generic.List[object]]::new()
    foreach ($artifact in @(
        (New-FileArtifact "score" $scorePath),
        (New-FileArtifact "hash_binding" $bindingPath),
        (New-FileArtifact "candidate_source_inventory" $SourceProof.candidate_inventory_path),
        (New-FileArtifact "candidate_source_delta" $SourceProof.delta_path),
        (New-FileArtifact "strong_replay_witness_inventory" `
            ([string]$SourceProof.witness_inventory_path)),
        (New-TreeArtifact "strong_replay_witness_tree" `
            ([string]$SourceProof.witness_root)),
        (New-TreeArtifact "source_proof_tree" $SourceProof.root),
        (New-FileArtifact "baseline_log" ([string]$Baseline.log)),
        (New-FileArtifact "static_log" ([string]$Static.log)),
        (New-FileArtifact "static_xml" ([string]$Static.result)),
        (New-FileArtifact "dynamic_log" ([string]$Dynamic.log)),
        (New-FileArtifact "dynamic_xml" ([string]$Dynamic.result)),
        (New-FileArtifact "fresh_log" ([string]$Fresh.log)),
        (New-FileArtifact "fresh_xml" ([string]$Fresh.result)),
        (New-TreeArtifact "evidence_tree" $evidenceDirectory),
        (New-FileArtifact "strong_architecture_proof" $strongArchitectureProofPath),
        (New-FileArtifact "visual_result" (Join-Path $OutputDirectory "visual-score.json")),
        (New-FileArtifact "pending_no_visual_score" (Join-Path $OutputDirectory "score.pending-no-visual.json"))
    )) {
        if ($null -ne $artifact) { $artifacts.Add($artifact) }
    }
    if ($null -ne $MaterializationProof) {
        $artifacts.Add((New-TreeArtifact `
            "materialization_proof_tree" $MaterializationProof.root))
        $artifacts.Add((New-FileArtifact `
            "materialization_provenance" $MaterializationProof.receipt_path))
    }
    $roles = @($artifacts | ForEach-Object { [string]$_.role })
    if (@($roles | Sort-Object -Unique).Count -ne $roles.Count) {
        throw "Run artifact roles are not unique."
    }
    if ($AuthorCalibration) {
        $requiredRoles = @(
            "score", "hash_binding", "candidate_source_inventory",
            "candidate_source_delta", "source_proof_tree", "baseline_log",
            "static_log", "static_xml", "dynamic_log", "dynamic_xml",
            "fresh_log", "fresh_xml", "evidence_tree")
        if ($CalibrationRole -in @("wrong_state_advances", "fixed_ui_no_persistence",
                "timeout_failure_hidden", "strong_equivalent")) {
            $requiredRoles += @("materialization_proof_tree", "materialization_provenance")
        }
        if ($CalibrationRole -eq "strong_equivalent") {
            $requiredRoles += @(
                "strong_replay_witness_inventory", "strong_replay_witness_tree",
                "strong_architecture_proof")
        }
        $missingRoles = @($requiredRoles | Where-Object { $roles -notcontains $_ })
        if ($missingRoles.Count -gt 0) {
            throw "Author calibration run is incomplete; missing artifact roles: $($missingRoles -join ', ')"
        }
    }
    $sealed = Get-SealedRunFiles
    $completedUtc = [DateTime]::UtcNow.ToString("o")
    $payload = [ordered]@{
        schema_version = 1
        protocol = "omnigame-unity-run-artifacts-v1"
        evaluator_session_id = $evaluationSessionId
        started_utc = $runStartedUtc
        completed_utc = $completedUtc
        calibration_role = $CalibrationRole
        author_calibration = [bool]$AuthorCalibration
        runner = [pscustomobject]@{
            path = "evaluation/scripts/run-evaluation.ps1"
            sha256 = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot "run-evaluation.ps1") -Algorithm SHA256).Hash.ToLowerInvariant()
            evaluator_definition_sha256 = [string]$binding.evaluator_sha256
            evaluator_protocol = [string]$ruleSet.evaluator_protocol
            rules_sha256 = [string]$binding.rules_sha256
        }
        source = [pscustomobject]@{
            project_path = [string]$binding.source_project_path
            project_tree_sha256 = [string]$binding.source_project_sha256
            gameplay_tree = Get-DetailedTreeSummary $SourceProof.candidate_inventory.gameplay_tree
            inventory_path = Get-RunRelativePath $SourceProof.candidate_inventory_path
            delta_path = Get-RunRelativePath $SourceProof.delta_path
            baseline_label = [string]$SourceProof.delta.baseline_label
            baseline_project_tree_sha256 = [string]$SourceProof.delta.baseline_project_tree_sha256
            excluded_materialization_paths = @($SourceProof.candidate_inventory.excluded_relative_paths)
            witness_inventory = if ($null -eq $SourceProof.witness_inventory) {
                $null
            } else {
                [pscustomobject][ordered]@{
                    path = Get-RunRelativePath $SourceProof.witness_inventory_path
                    schema_version = [int]$SourceProof.witness_inventory.schema_version
                    algorithm = [string]$SourceProof.witness_inventory.algorithm
                    inventory_sha256 = [string]$SourceProof.witness_inventory.inventory_sha256
                    file_count = [int]$SourceProof.witness_inventory.file_count
                    byte_count = [long]$SourceProof.witness_inventory.byte_count
                    entries = @($SourceProof.witness_inventory.entries)
                }
            }
            materialization_proof_paths = if ($null -eq $MaterializationProof) { @() } else {
                @($MaterializationProof.copied_relative_paths)
            }
        }
        bindings = [pscustomobject]@{
            source_project_sha256 = [string]$binding.source_project_sha256
            source_gameplay_tree_sha256 = [string]$binding.source_gameplay_tree_sha256
            post_source_gameplay_tree_sha256 = [string]$binding.post_source_gameplay_tree_sha256
            evaluator_sha256 = [string]$binding.evaluator_sha256
            private_evaluator_package_sha256 = [string]$binding.private_evaluator_package_sha256
            private_evaluator_package_complete_tree_sha256 = [string]$binding.private_evaluator_package_complete_tree_sha256
            rules_sha256 = [string]$binding.rules_sha256
            gdd_sha256 = [string]$binding.gdd_sha256
            public_specification_sha256 = [string]$binding.public_specification_sha256
            canonical_input_full_tree_sha256 = [string]$binding.canonical_input_full_tree_sha256
            canonical_gold_full_tree_sha256 = [string]$binding.canonical_gold_full_tree_sha256
            unity_editor_sha256 = [string]$binding.unity_editor_sha256
            unity_cli_sha256 = [string]$binding.unity_cli_sha256
        }
        phases = [pscustomobject]@{
            baseline = Get-PhaseReceipt $Baseline "baseline"
            static = Get-PhaseReceipt $Static "static"
            dynamic = Get-PhaseReceipt $Dynamic "dynamic"
            fresh = Get-PhaseReceipt $Fresh "fresh"
        }
        score_snapshot = [pscustomobject]@{
            valid_score = [bool]$score.valid_score
            formal_score_complete = [bool]$score.formal_score_complete
            candidate_status = [string]$score.candidate_status
            automatic_score = $score.automatic_score
            automatic_maximum_score = $score.automatic_maximum_score
            d6_status = [string]$score.dimensions.D6.status
            overall = $score.overall
            executable = [string]$score.outcomes.executable
            solved = [string]$score.outcomes.solved
        }
        artifacts = @($artifacts)
        sealed_tree = [pscustomobject]@{
            sha256 = [string]$sealed.sha256
            file_count = [int]$sealed.file_count
            byte_count = [long]$sealed.byte_count
            files = @($sealed.files)
        }
    }
    $payloadJson = $payload | ConvertTo-Json -Depth 30 -Compress
    $manifest = [pscustomobject]@{
        schema_version = 1
        payload_sha256 = Get-BytesHash ([Text.Encoding]::UTF8.GetBytes($payloadJson))
        payload = [pscustomobject]$payload
    }
    [IO.File]::WriteAllText($artifactManifestPath,
        ($manifest | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
    return $manifest
}

try {
try {
    New-Item -ItemType Directory -Path $ownedOutputDirectory | Out-Null
} finally {
    $outputDirectoryCreatedByThisInvocation =
        Test-Path -LiteralPath $ownedOutputDirectory -PathType Container
}
$OutputDirectory = (Resolve-Path -LiteralPath $ownedOutputDirectory).Path
Assert-ExactOwnedOutputPath $OutputDirectory $ownedOutputDirectory $repoTmpRoot
$ownedOutputDirectory = $OutputDirectory
$evidenceDirectory = Join-Path $OutputDirectory "evidence"
$scorePath = Join-Path $OutputDirectory "score.json"
$bindingPath = Join-Path $OutputDirectory "hash-binding.json"
$artifactManifestPath = Join-Path $OutputDirectory "run-artifact-manifest.json"
$strongArchitectureProofPath = Join-Path $OutputDirectory "strong-architecture-proof.json"
New-Item -ItemType Directory -Path $evidenceDirectory | Out-Null
New-Item -ItemType Directory -Path $hostTempPath -Force | Out-Null
$env:TEMP = $hostTempPath
$env:TMP = $hostTempPath
$sourceProjectPath = $ProjectPath
$protectedBaselinePath = (Resolve-Path -LiteralPath (Join-Path $demoRoot "input")).Path
# Gold is only needed by private author mutation/materialization workflows.
# Those workflows are not part of this candidate-only distribution.
$canonicalGoldPath = $null
$calibrationProofExclusions = @(Get-CalibrationProofExclusions $CalibrationRole)
$canonicalInputFullTree = Get-CompleteTreeBinding $protectedBaselinePath
$canonicalGoldFullTree = [pscustomobject]@{
    sha256 = $null
    file_count = $null
    directory_count = $null
    scope = "not_distributed_or_consumed_for_candidate_measurement"
}
$gddPath = Join-Path $protectedBaselinePath "GDD.md"
$publicTaskFiles = @(Get-PublicTaskFileList)
$gddHash = (Get-FileHash -LiteralPath $gddPath -Algorithm SHA256).Hash.ToLowerInvariant()
$publicSpecificationHash = Get-TreeHash $protectedBaselinePath $publicTaskFiles
$includePublicTaskFiles = -not [bool]$AuthorCalibration
Assert-ProtectedBaselineComplete $protectedBaselinePath $true
$sourceGameplayTree = Get-DetailedProjectTreeBinding `
    $sourceProjectPath $calibrationProofExclusions
$sourceGameplaySummary = Get-DetailedTreeSummary $sourceGameplayTree
if ($CalibrationRole -eq "strong_equivalent") {
    $strongReceiptPath = Join-Path $sourceProjectPath `
        "Assets\Benchmark\StrongEquivalentProvenance.json"
    $strongVerifier = Join-Path $evaluationRoot `
        "variants\verify-strong-materialization.ps1"
    $strongProofRaw = & $strongVerifier `
        -ProjectPath $sourceProjectPath `
        -ReceiptPath $strongReceiptPath `
        -OutputPath $strongArchitectureProofPath
    $strongProof = ($strongProofRaw -join [Environment]::NewLine) | ConvertFrom-Json
    if (-not [bool]$strongProof.passed -or
        -not (Test-DetailedTreeEqual `
            $strongProof.claim.scored_gameplay_project_tree $sourceGameplaySummary)) {
        throw "Strong-equivalent static architecture proof is not bound to the scored source gameplay tree."
    }
}
$protectedAudit = Compare-ProtectedTrees `
    $protectedBaselinePath $sourceProjectPath $includePublicTaskFiles ([bool]$AuthorCalibration)
$sourceHash = Get-TreeHash $sourceProjectPath `
    @("Assets", "Packages", "ProjectSettings") $calibrationProofExclusions
$evaluatorHash = Get-TreeHash $evaluationRoot @(
    "package", "rules.json", "mutants", "variants", "visual", "tests",
    "scripts/run-evaluation.ps1",
    "scripts/run-phase.ps1",
    "scripts/run-candidate-compile.ps1",
    "scripts/score-evaluation.ps1",
    "scripts/run-visual-scoring.ps1",
    "scripts/complete-evaluation-invocation.ps1",
    "scripts/classify-unity-phase-result.ps1")
$canonicalPackageCompleteTree = Get-CompleteTreeBinding (Join-Path $evaluationRoot "package")
if (-not (Test-Path -LiteralPath $UnityEditorPath -PathType Leaf)) {
    throw "UnityEditorPath must resolve to an executable file: $UnityEditorPath"
}
if (-not (Test-Path -LiteralPath $UnityCliPath -PathType Leaf)) {
    throw "UnityCliPath must resolve to an executable file: $UnityCliPath"
}
$editorHash = (Get-FileHash -LiteralPath $UnityEditorPath -Algorithm SHA256).Hash.ToLowerInvariant()
$cliHash = (Get-FileHash -LiteralPath $UnityCliPath -Algorithm SHA256).Hash.ToLowerInvariant()
if (-not $protectedAudit.compliant) {
    if ($AuthorCalibration) {
        $violationSummary = @($protectedAudit.violations |
            Select-Object -First 8 | ForEach-Object {
                "$([string]$_.kind):$([string]$_.path)"
            }) -join ", "
        # A positive/negative author control with protected-source drift is an
        # invalid calibration input, not a publishable disqualified candidate.
        # Throw the real policy cause before the normal candidate-only partial
        # result/manifest branch can obscure it with missing phase roles.
        throw "Protected author-calibration source violation: $violationSummary"
    }
    $binding = [pscustomobject]@{
        schema_version = 3
        generated_utc = [DateTime]::UtcNow.ToString("o")
        evaluation_session_id = $evaluationSessionId
        run_started_utc = $runStartedUtc
        calibration_role = $CalibrationRole
        source_hash_excluded_materialization_paths = @($calibrationProofExclusions)
        source_project_path = $sourceProjectPath
        source_project_sha256 = $sourceHash
        source_gameplay_tree_sha256 = [string]$sourceGameplayTree.sha256
        source_gameplay_tree = $sourceGameplaySummary
        post_source_gameplay_tree_sha256 = [string]$sourceGameplayTree.sha256
        post_source_gameplay_tree = $sourceGameplaySummary
        protected_baseline_path = $protectedBaselinePath
        protected_baseline_sha256 = $protectedAudit.baseline_sha256
        protected_candidate_sha256 = $protectedAudit.candidate_sha256
        canonical_input_full_tree_sha256 = $canonicalInputFullTree.sha256
        canonical_input_full_tree_file_count = $canonicalInputFullTree.file_count
        canonical_input_full_tree_directory_count = $canonicalInputFullTree.directory_count
        canonical_gold_full_tree_sha256 = $canonicalGoldFullTree.sha256
        canonical_gold_full_tree_file_count = $canonicalGoldFullTree.file_count
        canonical_gold_full_tree_directory_count = $canonicalGoldFullTree.directory_count
        gdd_sha256 = $gddHash
        public_specification_sha256 = $publicSpecificationHash
        evaluator_sha256 = $evaluatorHash
        private_evaluator_package_complete_tree_sha256 = $canonicalPackageCompleteTree.sha256
        rules_sha256 = (Get-FileHash -LiteralPath (Join-Path $evaluationRoot "rules.json") -Algorithm SHA256).Hash.ToLowerInvariant()
        unity_editor_sha256 = $editorHash
        unity_editor = $UnityEditorPath
        unity_cli_sha256 = $cliHash
        unity_cli = $UnityCliPath
    }
    [System.IO.File]::WriteAllText($bindingPath,
        ($binding | ConvertTo-Json -Depth 6),
        [System.Text.UTF8Encoding]::new($false))
    $report = [pscustomobject]@{
        schema_version = [int]$ruleSet.schema_version
        evaluator_protocol = [string]$ruleSet.evaluator_protocol
        project_path = $sourceProjectPath
        valid_score = $true
        formal_score_complete = $false
        candidate_status = "policy_violation_disqualified"
        dimensions = New-UnevaluatedDimensions 0 "disqualified"
        score = $null
        overall = $null
        raw_score = 0
        automatic_score = 0
        automatic_maximum_score = [double]$ruleSet.automatic_maximum_score
        maximum_score = [double]$ruleSet.maximum_score
        policy = "protected_paths_must_match_input_baseline"
        author_calibration = [bool]$AuthorCalibration
        protected_path_audit = $protectedAudit
        hash_binding = $binding
    }
    [System.IO.File]::WriteAllText($scorePath,
        ($report | ConvertTo-Json -Depth 12),
        [System.Text.UTF8Encoding]::new($false))
    $comparisonBaseline = if ($CalibrationRole -in @("candidate", "input")) {
        $protectedBaselinePath
    } else { $canonicalGoldPath }
    $sourceProof = Write-SourceProof `
        $sourceProjectPath $comparisonBaseline $CalibrationRole $calibrationProofExclusions
    $materializationProof = Write-MaterializationProof `
        $sourceProjectPath $CalibrationRole $calibrationProofExclusions
    $null = Write-RunArtifactManifest `
        $null $null $null $null $sourceProof $materializationProof
    $reportJson = $report | ConvertTo-Json -Depth 12
    Complete-EvaluationInvocation -ReportJson $reportJson -ExitCode 0
}

$coldCopyPath = Join-Path $OutputDirectory "_candidate-cold"
$privatePackagePath = Join-Path $OutputDirectory "_private-evaluator-package"
$coldCopyCreated = $false
$privatePackageCreated = $false
try {
    if (Test-Path -LiteralPath $coldCopyPath) {
        throw "Cold-copy path already exists; use a fresh OutputDirectory: $coldCopyPath"
    }
    New-Item -ItemType Directory -Path $coldCopyPath | Out-Null
    $coldCopyCreated = $true
    if (Test-Path -LiteralPath $privatePackagePath) {
        throw "Private evaluator package path already exists; use a fresh OutputDirectory: $privatePackagePath"
    }
    try {
        Copy-Item -LiteralPath (Join-Path $evaluationRoot "package") `
            -Destination $privatePackagePath -Recurse
    } finally {
        $privatePackageCreated = Test-Path -LiteralPath $privatePackagePath -PathType Container
    }
    $privatePackagePath = (Resolve-Path -LiteralPath $privatePackagePath).Path
    $canonicalPackageHash = Get-TreeHash (Join-Path $evaluationRoot "package") @(".")
    $privatePackageHash = Get-TreeHash $privatePackagePath @(".")
    if (-not [string]::Equals($canonicalPackageHash, $privatePackageHash,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Private evaluator-package copy differs from the canonical evaluator package."
    }
    foreach ($rootName in @("Assets", "Packages", "ProjectSettings")) {
        $sourceRoot = Join-Path $sourceProjectPath $rootName
        if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
            throw "Candidate is missing required Unity directory: $sourceRoot"
        }
        Copy-Item -LiteralPath $sourceRoot -Destination $coldCopyPath -Recurse -Force
    }
    $evaluatedProjectPath = (Resolve-Path -LiteralPath $coldCopyPath).Path

    $coldHash = Get-TreeHash $evaluatedProjectPath `
        @("Assets", "Packages", "ProjectSettings") $calibrationProofExclusions
    $coldGameplayTree = Get-DetailedProjectTreeBinding `
        $evaluatedProjectPath $calibrationProofExclusions
    $coldGameplaySummary = Get-DetailedTreeSummary $coldGameplayTree
    if (-not [string]::Equals($sourceHash, $coldHash,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Cold-copy hash differs from the source project before evaluation."
    }
    if (-not (Test-DetailedTreeEqual $sourceGameplaySummary $coldGameplaySummary)) {
        throw "Cold-copy gameplay tree differs from the source project before evaluation."
    }
    $binding = [pscustomobject]@{
        schema_version = 3
        generated_utc = [DateTime]::UtcNow.ToString("o")
        evaluation_session_id = $evaluationSessionId
        run_started_utc = $runStartedUtc
        calibration_role = $CalibrationRole
        source_hash_excluded_materialization_paths = @($calibrationProofExclusions)
        source_project_path = $sourceProjectPath
        evaluated_cold_copy = $evaluatedProjectPath
        source_project_sha256 = $sourceHash
        evaluated_cold_copy_sha256 = $coldHash
        source_gameplay_tree_sha256 = [string]$sourceGameplayTree.sha256
        source_gameplay_tree = $sourceGameplaySummary
        evaluated_cold_copy_gameplay_tree_sha256 = [string]$coldGameplayTree.sha256
        evaluated_cold_copy_gameplay_tree = $coldGameplaySummary
        protected_baseline_path = $protectedBaselinePath
        protected_baseline_sha256 = $protectedAudit.baseline_sha256
        protected_candidate_sha256 = $protectedAudit.candidate_sha256
        protected_file_count = $protectedAudit.baseline_file_count
        canonical_input_full_tree_sha256 = $canonicalInputFullTree.sha256
        canonical_input_full_tree_file_count = $canonicalInputFullTree.file_count
        canonical_input_full_tree_directory_count = $canonicalInputFullTree.directory_count
        canonical_gold_full_tree_sha256 = $canonicalGoldFullTree.sha256
        canonical_gold_full_tree_file_count = $canonicalGoldFullTree.file_count
        canonical_gold_full_tree_directory_count = $canonicalGoldFullTree.directory_count
        gdd_sha256 = $gddHash
        public_specification_sha256 = $publicSpecificationHash
        private_evaluator_package_sha256 = $privatePackageHash
        private_evaluator_package_complete_tree_sha256 = $canonicalPackageCompleteTree.sha256
        evaluator_sha256 = $evaluatorHash
        rules_sha256 = (Get-FileHash -LiteralPath (Join-Path $evaluationRoot "rules.json") -Algorithm SHA256).Hash.ToLowerInvariant()
        unity_editor_sha256 = $editorHash
        unity_editor = $UnityEditorPath
        unity_cli_sha256 = $cliHash
        unity_cli = $UnityCliPath
        author_calibration = [bool]$AuthorCalibration
    }
    [System.IO.File]::WriteAllText($bindingPath,
        ($binding | ConvertTo-Json -Depth 5),
        [System.Text.UTF8Encoding]::new($false))

    $baselineDirectory = Join-Path $OutputDirectory "baseline"
    $baseline = Invoke-JsonScript (Join-Path $PSScriptRoot "run-candidate-compile.ps1") @{
        ProjectPath = $evaluatedProjectPath
        UnityEditorPath = $UnityEditorPath
        UnityCliPath = $UnityCliPath
        OutputDirectory = $baselineDirectory
        EvaluationSessionId = $evaluationSessionId
        NoExitOnCompletion = $true
    }
    if ([string]$baseline.execution_status -eq "infrastructure_error") {
        throw "Baseline Unity infrastructure failed. See $($baseline.log)"
    }
    $skipScoredPhases = $false
    if ([string]$baseline.execution_status -eq "candidate_failed") {
        $report = [pscustomobject]@{
            schema_version = [int]$ruleSet.schema_version
            evaluator_protocol = [string]$ruleSet.evaluator_protocol
            project_path = $sourceProjectPath
            valid_score = $true
            formal_score_complete = $false
            candidate_status = "static_gate_failed"
            dimensions = New-UnevaluatedDimensions 0 "not_reached"
            score = $null
            overall = $null
            raw_score = 0
            automatic_score = 0
            automatic_maximum_score = [double]$ruleSet.automatic_maximum_score
            maximum_score = [double]$ruleSet.maximum_score
            candidate_failure = $baseline
            author_calibration = [bool]$AuthorCalibration
            hash_binding = $binding
        }
        [System.IO.File]::WriteAllText($scorePath,
            ($report | ConvertTo-Json -Depth 10),
            [System.Text.UTF8Encoding]::new($false))
        $skipScoredPhases = $true
    }

    if (-not $skipScoredPhases) {
    $settingsPath = Join-Path $evaluatedProjectPath "ProjectSettings\ProjectSettings.asset"
    $settingsBytes = [System.IO.File]::ReadAllBytes($settingsPath)
    $isolationCompany = "OmniGameSignCircuitEvaluator"
    $identity = "SignCircuit_" + [Guid]::NewGuid().ToString("N")
    $localAppData = [Environment]::GetFolderPath(
        [Environment+SpecialFolder]::LocalApplicationData)
    $isolatedPersistentPath = Join-Path `
        (Join-Path (Join-Path (Split-Path -Parent $localAppData) "LocalLow") `
            $isolationCompany) $identity
    if (Test-Path -LiteralPath $isolatedPersistentPath) {
        throw "Fresh persistence isolation path unexpectedly exists: $isolatedPersistentPath"
    }
    $binding | Add-Member -MemberType NoteProperty -Name persistence_isolation `
        -Value ([pscustomobject]@{
            company = $isolationCompany
            product = $identity
            persistent_data_path = $isolatedPersistentPath
            player_prefs_registry_path =
                "Software\Unity\UnityEditor\$isolationCompany\$identity"
            cleanup_completed = $false
        }) -Force
    try {
        $settingsText = [System.Text.Encoding]::UTF8.GetString($settingsBytes)
        if ($settingsText -notmatch '(?m)^  companyName:' -or
            $settingsText -notmatch '(?m)^  productName:') {
            throw "ProjectSettings.asset has no companyName/productName fields."
        }
        $settingsText = $settingsText -replace '(?m)^  companyName:.*$', "  companyName: $isolationCompany"
        $settingsText = $settingsText -replace '(?m)^  productName:.*$', "  productName: $identity"
        [System.IO.File]::WriteAllText($settingsPath, $settingsText,
            [System.Text.UTF8Encoding]::new($false))

        $static = Invoke-JsonScript (Join-Path $PSScriptRoot "run-phase.ps1") @{
            ProjectPath = $evaluatedProjectPath; Phase = "Static"; UnityEditorPath = $UnityEditorPath
            UnityCliPath = $UnityCliPath
            OutputDirectory = (Join-Path $OutputDirectory "static")
            EvidenceDirectory = $evidenceDirectory; EvaluatorPackagePath = $privatePackagePath
            EvaluationSessionId = $evaluationSessionId
            NoExitOnCompletion = $true
        }
        Assert-PhaseUsable $static
        if (-not (Test-StaticFullPass ([string]$static.result))) {
            $failureClassification = Get-StaticFailureClassification ([string]$static.result)
            $retryReasons = @($failureClassification.non_candidate_failures)
            if ($retryReasons.Count -gt 0 -and
                -not [bool]$failureClassification.has_candidate_failure) {
                $firstStatic = $static
                $static = Invoke-JsonScript (Join-Path $PSScriptRoot "run-phase.ps1") @{
                    ProjectPath = $evaluatedProjectPath; Phase = "Static"; UnityEditorPath = $UnityEditorPath
                    UnityCliPath = $UnityCliPath
                    OutputDirectory = (Join-Path $OutputDirectory "static-retry")
                    EvidenceDirectory = $evidenceDirectory; EvaluatorPackagePath = $privatePackagePath
                    EvaluationSessionId = $evaluationSessionId
                    NoExitOnCompletion = $true
                }
                Assert-PhaseUsable $static
                $binding | Add-Member -MemberType NoteProperty -Name static_retry -Value ([pscustomobject]@{
                    attempted = $true
                    reason = "First warmed-cold Static run had a non-candidate-marked failure."
                    trigger_messages = $retryReasons
                    first_result = [string]$firstStatic.result
                    first_log = [string]$firstStatic.log
                    authoritative_result = [string]$static.result
                    authoritative_log = [string]$static.log
                }) -Force
            }
        }
        if (-not (Test-StaticFullPass ([string]$static.result))) {
            $null = & (Join-Path $PSScriptRoot "score-evaluation.ps1") `
                -StaticResultPath ([string]$static.result) -ProjectPath $sourceProjectPath `
                -HashBindingPath $bindingPath -OutputPath $scorePath -NoExitOnInvalid
        } else {
            $dynamic = Invoke-JsonScript (Join-Path $PSScriptRoot "run-phase.ps1") @{
                ProjectPath = $evaluatedProjectPath; Phase = "Dynamic"; UnityEditorPath = $UnityEditorPath
                UnityCliPath = $UnityCliPath
                OutputDirectory = (Join-Path $OutputDirectory "dynamic")
                EvidenceDirectory = $evidenceDirectory; EvaluatorPackagePath = $privatePackagePath
                EvaluationSessionId = $evaluationSessionId
                NoExitOnCompletion = $true
            }
            if ([string]$dynamic.failure_kind -eq "evaluator_health_failure") {
                $firstDynamic = $dynamic
                Clear-PhaseEvidence 'Dynamic'
                $null = Remove-IsolatedUnityPersistence $isolationCompany $identity
                $dynamic = Invoke-JsonScript (Join-Path $PSScriptRoot "run-phase.ps1") @{
                    ProjectPath = $evaluatedProjectPath; Phase = "Dynamic"; UnityEditorPath = $UnityEditorPath
                    UnityCliPath = $UnityCliPath
                    OutputDirectory = (Join-Path $OutputDirectory "dynamic-health-retry")
                    EvidenceDirectory = $evidenceDirectory; EvaluatorPackagePath = $privatePackagePath
                    EvaluationSessionId = $evaluationSessionId
                    NoExitOnCompletion = $true
                }
                $binding | Add-Member -MemberType NoteProperty -Name dynamic_health_retry `
                    -Value ([pscustomobject]@{
                        attempted = $true
                        reason = "The first isolated Dynamic evaluator-health prerequisite failed; one bounded retry was permitted."
                        first_result = [string]$firstDynamic.result
                        first_log = [string]$firstDynamic.log
                        first_failures = @($firstDynamic.evaluator_health_failures)
                        authoritative_result = [string]$dynamic.result
                        authoritative_log = [string]$dynamic.log
                    }) -Force
            }
            Assert-PhaseUsable $dynamic
            $fresh = Invoke-JsonScript (Join-Path $PSScriptRoot "run-phase.ps1") @{
                ProjectPath = $evaluatedProjectPath; Phase = "Fresh"; UnityEditorPath = $UnityEditorPath
                UnityCliPath = $UnityCliPath
                OutputDirectory = (Join-Path $OutputDirectory "fresh")
                EvidenceDirectory = $evidenceDirectory; EvaluatorPackagePath = $privatePackagePath
                EvaluationSessionId = $evaluationSessionId
                NoExitOnCompletion = $true
            }
            if ([string]$fresh.failure_kind -eq "evaluator_health_failure") {
                $firstFresh = $fresh
                Clear-PhaseEvidence 'Fresh'
                $fresh = Invoke-JsonScript (Join-Path $PSScriptRoot "run-phase.ps1") @{
                    ProjectPath = $evaluatedProjectPath; Phase = "Fresh"; UnityEditorPath = $UnityEditorPath
                    UnityCliPath = $UnityCliPath
                    OutputDirectory = (Join-Path $OutputDirectory "fresh-health-retry")
                    EvidenceDirectory = $evidenceDirectory; EvaluatorPackagePath = $privatePackagePath
                    EvaluationSessionId = $evaluationSessionId
                    NoExitOnCompletion = $true
                }
                $binding | Add-Member -MemberType NoteProperty -Name fresh_health_retry `
                    -Value ([pscustomobject]@{
                        attempted = $true
                        reason = "The first isolated Fresh evaluator-health prerequisite failed; one bounded retry was permitted."
                        first_result = [string]$firstFresh.result
                        first_log = [string]$firstFresh.log
                        first_failures = @($firstFresh.evaluator_health_failures)
                        authoritative_result = [string]$fresh.result
                        authoritative_log = [string]$fresh.log
                    }) -Force
            }
            Assert-PhaseUsable $fresh
            $dynamicUnityProcessId = Get-UnityProcessIdFromPhaseReceipt `
                $dynamic 'Dynamic'
            $freshUnityProcessId = Get-UnityProcessIdFromPhaseReceipt `
                $fresh 'Fresh'
            if ($dynamicUnityProcessId -eq $freshUnityProcessId) {
                throw "Dynamic and Fresh phase receipts identify the same Unity PID."
            }

            $visualResultPath = ""
            if ($RunVisualScoring) {
                $visualResultPath = Join-Path $OutputDirectory "visual-score.json"
                $visualParameters = @{
                    CandidateEvidenceDirectory = $evidenceDirectory
                    OutputPath = $visualResultPath
                    Model = $VisualModel
                    NoExitOnInvalid = $true
                }
                $visualParameters["BaseUrl"] = $VisualBaseUrl
                $visualParameters["ApiKeyEnvironment"] = $VisualApiKeyEnvironment
                $null = Invoke-JsonScript (Join-Path $PSScriptRoot "run-visual-scoring.ps1") `
                    $visualParameters
            }

            $scoreParameters = @{
                StaticResultPath = [string]$static.result
                DynamicResultPath = [string]$dynamic.result
                FreshResultPath = [string]$fresh.result
                EvidenceDirectory = $evidenceDirectory
                EvaluationSessionId = $evaluationSessionId
                DynamicProcessId = $dynamicUnityProcessId
                FreshProcessId = $freshUnityProcessId
                DynamicStartedUtc = [string]$dynamic.started_utc
                DynamicCompletedUtc = [string]$dynamic.completed_utc
                FreshStartedUtc = [string]$fresh.started_utc
                FreshCompletedUtc = [string]$fresh.completed_utc
                ProjectPath = $sourceProjectPath
                HashBindingPath = $bindingPath
                OutputPath = $scorePath
                NoExitOnInvalid = $true
            }
            if (-not [string]::IsNullOrWhiteSpace($visualResultPath)) {
                $scoreParameters["VisualResultPath"] = $visualResultPath
                $scoreParameters["VisualEvidenceDirectory"] = $evidenceDirectory
            }
            $null = & (Join-Path $PSScriptRoot "score-evaluation.ps1") @scoreParameters
            if ($RunVisualScoring) {
                $visualGateScore = Get-Content -Raw -Encoding UTF8 -LiteralPath $scorePath |
                    ConvertFrom-Json
                $formalVisualGatePassed = [bool]$visualGateScore.formal_score_complete -and
                    [string]$visualGateScore.dimensions.D6.status -eq "evaluated" -and
                    @($visualGateScore.dimensions.D6.rounds).Count -eq 3 -and
                    $null -ne $visualGateScore.overall
                if (-not $formalVisualGatePassed) {
                    $pendingScorePath = Join-Path $OutputDirectory "score.pending-no-visual.json"
                    $null = & (Join-Path $PSScriptRoot "score-evaluation.ps1") `
                        -StaticResultPath ([string]$static.result) `
                        -DynamicResultPath ([string]$dynamic.result) `
                        -FreshResultPath ([string]$fresh.result) `
                        -EvidenceDirectory $evidenceDirectory `
                        -EvaluationSessionId $evaluationSessionId `
                        -DynamicProcessId $dynamicUnityProcessId `
                        -FreshProcessId $freshUnityProcessId `
                        -DynamicStartedUtc ([string]$dynamic.started_utc) `
                        -DynamicCompletedUtc ([string]$dynamic.completed_utc) `
                        -FreshStartedUtc ([string]$fresh.started_utc) `
                        -FreshCompletedUtc ([string]$fresh.completed_utc) `
                        -ProjectPath $sourceProjectPath `
                        -HashBindingPath $bindingPath `
                        -OutputPath $pendingScorePath `
                        -NoExitOnInvalid
                    $binding | Add-Member -MemberType NoteProperty -Name formal_visual_gate `
                        -Value ([pscustomobject]@{
                            requested = $true
                            passed = $false
                            visual_result_path = $visualResultPath
                            diagnostic_score_path = $scorePath
                            separate_pending_score_path = $pendingScorePath
                            reason = "Formal visual execution was requested but score.json is not a complete evaluated three-round D6 result with non-null Overall."
                        }) -Force
                } else {
                    $binding | Add-Member -MemberType NoteProperty -Name formal_visual_gate `
                        -Value ([pscustomobject]@{
                            requested = $true; passed = $true
                            visual_result_path = $visualResultPath
                            diagnostic_score_path = $scorePath
                            separate_pending_score_path = $null
                            reason = $null
                        }) -Force
                }
            }
        }
    } finally {
        [System.IO.File]::WriteAllBytes($settingsPath, $settingsBytes)
        $persistenceCleanup = Remove-IsolatedUnityPersistence `
            $isolationCompany $identity
        $binding.persistence_isolation = [pscustomobject]@{
            company = $isolationCompany
            product = $identity
            persistent_data_path = $isolatedPersistentPath
            player_prefs_registry_path =
                "Software\Unity\UnityEditor\$isolationCompany\$identity"
            cleanup_completed =
                [bool]$persistenceCleanup.persistent_path_absent_after_cleanup -and
                [bool]$persistenceCleanup.registry_key_absent_after_cleanup
        }
    }
    }

    $postSourceHash = Get-TreeHash $sourceProjectPath `
        @("Assets", "Packages", "ProjectSettings") $calibrationProofExclusions
    $postColdHash = Get-TreeHash $evaluatedProjectPath `
        @("Assets", "Packages", "ProjectSettings") $calibrationProofExclusions
    $postSourceGameplayTree = Get-DetailedProjectTreeBinding `
        $sourceProjectPath $calibrationProofExclusions
    $postColdGameplayTree = Get-DetailedProjectTreeBinding `
        $evaluatedProjectPath $calibrationProofExclusions
    $postSourceGameplaySummary = Get-DetailedTreeSummary $postSourceGameplayTree
    $postColdGameplaySummary = Get-DetailedTreeSummary $postColdGameplayTree
    $postPrivatePackageHash = Get-TreeHash $privatePackagePath @(".")
    $postGddHash = (Get-FileHash -LiteralPath $gddPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $postPublicSpecificationHash = Get-TreeHash $protectedBaselinePath $publicTaskFiles
    $postColdProjection = Compare-ColdSourceProjection $sourceProjectPath $evaluatedProjectPath
    $postSourceProtected = Compare-ProtectedTrees `
        $protectedBaselinePath $sourceProjectPath $includePublicTaskFiles ([bool]$AuthorCalibration)
    $postColdProtected = Compare-ProtectedTrees `
        $protectedBaselinePath $evaluatedProjectPath $false ([bool]$AuthorCalibration)
    if (-not [string]::Equals($sourceHash, $postSourceHash,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "The source candidate changed while evaluation was running."
    }
    if (-not (Test-DetailedTreeEqual `
            $sourceGameplaySummary $postSourceGameplaySummary)) {
        throw "The source candidate gameplay tree changed while evaluation was running."
    }
    if (-not $postColdProjection.compliant) {
        $summary = @($postColdProjection.violations | Select-Object -First 5 |
            ForEach-Object { "$($_.kind):$($_.path)" }) -join ", "
        throw "The evaluated cold copy changed outside permitted Unity .meta generation: $summary"
    }
    if (-not [string]::Equals($privatePackageHash, $postPrivatePackageHash,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "The private evaluator package changed during evaluation."
    }
    if (-not [string]::Equals($gddHash, $postGddHash,
            [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($publicSpecificationHash, $postPublicSpecificationHash,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "The frozen public specification changed during evaluation."
    }
    if (-not $postSourceProtected.compliant -or -not $postColdProtected.compliant) {
        throw "Protected paths drifted during evaluation."
    }
    $binding | Add-Member -MemberType NoteProperty -Name post_source_project_sha256 `
        -Value $postSourceHash -Force
    $binding | Add-Member -MemberType NoteProperty -Name post_source_gameplay_tree_sha256 `
        -Value ([string]$postSourceGameplayTree.sha256) -Force
    $binding | Add-Member -MemberType NoteProperty -Name post_source_gameplay_tree `
        -Value $postSourceGameplaySummary -Force
    $binding | Add-Member -MemberType NoteProperty -Name post_evaluated_cold_copy_sha256 `
        -Value $postColdHash -Force
    $binding | Add-Member -MemberType NoteProperty `
        -Name post_evaluated_cold_copy_gameplay_tree_sha256 `
        -Value ([string]$postColdGameplayTree.sha256) -Force
    $binding | Add-Member -MemberType NoteProperty `
        -Name post_evaluated_cold_copy_gameplay_tree `
        -Value $postColdGameplaySummary -Force
    $binding | Add-Member -MemberType NoteProperty -Name post_cold_source_projection `
        -Value $postColdProjection -Force
    $binding | Add-Member -MemberType NoteProperty -Name post_private_evaluator_package_sha256 `
        -Value $postPrivatePackageHash -Force
    $binding | Add-Member -MemberType NoteProperty -Name post_gdd_sha256 `
        -Value $postGddHash -Force
    $binding | Add-Member -MemberType NoteProperty -Name post_public_specification_sha256 `
        -Value $postPublicSpecificationHash -Force
    $binding | Add-Member -MemberType NoteProperty -Name post_protected_candidate_sha256 `
        -Value $postSourceProtected.candidate_sha256 -Force
    [System.IO.File]::WriteAllText($bindingPath,
        ($binding | ConvertTo-Json -Depth 8),
        [System.Text.UTF8Encoding]::new($false))
    $pendingNoVisualPath = Join-Path $OutputDirectory "score.pending-no-visual.json"
    if (Test-Path -LiteralPath $pendingNoVisualPath -PathType Leaf) {
        $pendingNoVisual = Get-Content -Raw -Encoding UTF8 -LiteralPath $pendingNoVisualPath |
            ConvertFrom-Json
        $pendingNoVisual.hash_binding = $binding
        [System.IO.File]::WriteAllText($pendingNoVisualPath,
            ($pendingNoVisual | ConvertTo-Json -Depth 12),
            [System.Text.UTF8Encoding]::new($false))
    }
    if (Test-Path -LiteralPath $scorePath -PathType Leaf) {
        $finalReport = Get-Content -Raw -Encoding UTF8 -LiteralPath $scorePath | ConvertFrom-Json
        $finalReport.hash_binding = $binding
        $finalReport | Add-Member -MemberType NoteProperty -Name author_calibration `
            -Value ([bool]$AuthorCalibration) -Force
        [System.IO.File]::WriteAllText($scorePath,
            ($finalReport | ConvertTo-Json -Depth 12),
            [System.Text.UTF8Encoding]::new($false))
        $finalReportJson = $finalReport | ConvertTo-Json -Depth 12
        if (-not [bool]$finalReport.valid_score) {
            $invalidFinalReport = $finalReport
            $invalidFinalReportJson = $finalReportJson
        } else {
            $comparisonBaseline = if ($CalibrationRole -in @("candidate", "input")) {
                $protectedBaselinePath
            } else { $canonicalGoldPath }
            $sourceProof = Write-SourceProof `
                $sourceProjectPath $comparisonBaseline $CalibrationRole $calibrationProofExclusions
            $materializationProof = Write-MaterializationProof `
                $sourceProjectPath $CalibrationRole $calibrationProofExclusions
            $null = Write-RunArtifactManifest `
                $baseline $static $dynamic $fresh $sourceProof $materializationProof
            if ($RunVisualScoring -and
                ($null -eq $binding.formal_visual_gate -or
                 -not [bool]$binding.formal_visual_gate.passed)) {
                Complete-EvaluationInvocation `
                    -ReportJson $finalReportJson -ExitCode 8
            }
            Complete-EvaluationInvocation -ReportJson $finalReportJson -ExitCode 0
        }
    } else {
        throw "Evaluator completed without score.json."
    }
} finally {
    $cleanupErrors = [System.Collections.Generic.List[string]]::new()
    if ($coldCopyCreated -and (Test-Path -LiteralPath $coldCopyPath)) {
        try { Remove-TreeRobust $coldCopyPath $OutputDirectory }
        catch { $cleanupErrors.Add($_.Exception.Message) }
    }
    if ($privatePackageCreated -and (Test-Path -LiteralPath $privatePackagePath)) {
        try { Remove-TreeRobust $privatePackagePath $OutputDirectory }
        catch { $cleanupErrors.Add($_.Exception.Message) }
    }
    if ($cleanupErrors.Count -gt 0) {
        throw "Evaluation scratch cleanup failed: $($cleanupErrors -join ' | ')"
    }
}
if ($null -ne $invalidFinalReport) {
    $null = Complete-InvalidEvaluationOutput `
        -Path $OutputDirectory `
        -ExpectedOwnedPath $ownedOutputDirectory `
        -RepositoryTmpRoot $repoTmpRoot `
        -ReasonKind "score_valid_score_false" `
        -InvalidReport $invalidFinalReport `
        -SessionId $evaluationSessionId `
        -CandidateProjectPath $ProjectPath `
        -Retain:$RetainInvalidDiagnostics
    Complete-EvaluationInvocation -ReportJson $invalidFinalReportJson -ExitCode 3
}
} catch {
    $caughtError = $_
    $message = $caughtError.Exception.Message
    $binding = if (Test-Path -LiteralPath $bindingPath -PathType Leaf) {
        try { Get-Content -Raw -Encoding UTF8 -LiteralPath $bindingPath | ConvertFrom-Json }
        catch { $null }
    } else { $null }
    $invalidReport = [pscustomobject]@{
        schema_version = [int]$ruleSet.schema_version
        evaluator_protocol = [string]$ruleSet.evaluator_protocol
        generated_utc = [DateTime]::UtcNow.ToString("o")
        project_path = $ProjectPath
        valid_score = $false
        formal_score_complete = $false
        candidate_status = "invalid"
        validation_reasons = @("Evaluator infrastructure failure: $message")
        dimensions = New-UnevaluatedDimensions $null "invalid"
        score = $null
        overall = $null
        raw_score = $null
        automatic_score = $null
        automatic_maximum_score = [double]$ruleSet.automatic_maximum_score
        maximum_score = [double]$ruleSet.maximum_score
        hash_binding = $binding
    }
    $invalidFinalizationFailure = $null
    if ($outputDirectoryCreatedByThisInvocation -and
        (Test-Path -LiteralPath $ownedOutputDirectory)) {
        $diagnosticScoreWriteFailure = ""
        if ($RetainInvalidDiagnostics) {
            try {
                [System.IO.File]::WriteAllText($scorePath,
                    ($invalidReport | ConvertTo-Json -Depth 12),
                    [System.Text.UTF8Encoding]::new($false))
            } catch {
                $diagnosticScoreWriteFailure = $_.Exception.Message
            }
        }
        try {
            $null = Complete-InvalidEvaluationOutput `
                -Path $ownedOutputDirectory `
                -ExpectedOwnedPath $ownedOutputDirectory `
                -RepositoryTmpRoot $repoTmpRoot `
                -ReasonKind "evaluator_exception" `
                -InvalidReport $invalidReport `
                -SessionId $evaluationSessionId `
                -CandidateProjectPath $ProjectPath `
                -Retain:$RetainInvalidDiagnostics `
                -ExceptionMessage $message `
                -DiagnosticScoreWriteFailure $diagnosticScoreWriteFailure
        } catch {
            $invalidFinalizationFailure = $_.Exception.Message
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($invalidFinalizationFailure)) {
        throw "Evaluator failed ('$message'); invalid OutputDirectory finalization also failed: $invalidFinalizationFailure"
    }
    $invalidReportJson = $invalidReport | ConvertTo-Json -Depth 12
    Complete-EvaluationInvocation -ReportJson $invalidReportJson -ExitCode 3
} finally {
    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp
    if (Test-Path -LiteralPath $hostTempPath) {
        Remove-TreeRobust $hostTempPath $repoTmpRoot
    }
}
