[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [string]$UnityCliPath=$env:UNITY_CLI,
    [string]$UnityEditorPath=$env:UNITY_EDITOR,
    [switch]$RetainInvalidDiagnostics
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..')).TrimEnd('\')
$repoTmp = Join-Path $repoRoot 'tmp'
$repoRuns = Join-Path $repoRoot 'runs'
$project = (Resolve-Path -LiteralPath $ProjectPath).Path.TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
$processHelperPath = (Resolve-Path -LiteralPath (
    Join-Path $PSScriptRoot 'scripts\invoke-bounded-cli-process.ps1')).Path
. $processHelperPath
$sourceBindingHelperPath = (Resolve-Path -LiteralPath (
    Join-Path $PSScriptRoot 'scripts\get-current-source-binding.ps1')).Path
. $sourceBindingHelperPath
$persistenceHelperPath = (Resolve-Path -LiteralPath (
    Join-Path $PSScriptRoot 'scripts\unity-persistence-scope.ps1')).Path
. $persistenceHelperPath
$rulesPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'rules.json')).Path
$sourceBindingBefore = Get-ArrowEscapeCurrentSourceBinding $PSScriptRoot $rulesPath

function Test-Under([string]$Path, [string]$Root) {
    $candidate = [IO.Path]::GetFullPath($Path).TrimEnd('\') + '\'
    $boundary = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    return $candidate.StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-NoReparsePointAncestor([string]$Path, [string]$AllowedRoot) {
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $fullRoot = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\', '/')
    if (-not (Test-Under $fullPath $fullRoot)) {
        throw "Path must be a strict child of its allowed repository root: $fullPath"
    }
    $cursor = Split-Path -Parent $fullPath
    while (-not [string]::IsNullOrWhiteSpace($cursor)) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Path cannot traverse a reparse-point ancestor: $cursor"
            }
        }
        if ([string]::Equals($cursor, $fullRoot,
                [StringComparison]::OrdinalIgnoreCase)) {
            return
        }
        $parent = Split-Path -Parent $cursor
        if ([string]::Equals($parent, $cursor,
                [StringComparison]::OrdinalIgnoreCase)) { break }
        $cursor = $parent
    }
    throw "Path ancestor walk did not reach its allowed repository root: $fullPath"
}

foreach ($path in @($project, $output)) {
    if (-not (Test-Under $path $repoRoot)) {
        throw "Project and output must stay inside repository root: $repoRoot (got $path)"
    }
}
if (-not ((Test-Under $output $repoTmp) -or (Test-Under $output $repoRuns))) {
    throw "OutputDirectory must be a new child path under repository tmp/ or runs/: $output"
}
$outputAllowedRoot = if (Test-Under $output $repoTmp) { $repoTmp } else { $repoRuns }
Assert-NoReparsePointAncestor $output $outputAllowedRoot
if (Test-Under $output $project) {
    throw "OutputDirectory must not be inside the candidate project: $output"
}
if ($RetainInvalidDiagnostics -and -not (Test-Under $output $repoTmp)) {
    throw "RetainInvalidDiagnostics is author-only and requires OutputDirectory under $repoTmp"
}
if (-not (Test-Path -LiteralPath (Join-Path $project 'Assets') -PathType Container) -or
    -not (Test-Path -LiteralPath (Join-Path $project 'ProjectSettings\ProjectVersion.txt') -PathType Leaf)) {
    throw "Not a Unity project: $project"
}
if (Test-Path -LiteralPath $output) {
    throw "Output directory must not already exist: $output"
}
foreach ($tool in @($UnityCliPath, $UnityEditorPath)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Pinned Unity tool is missing: $tool"
    }
}

New-Item -ItemType Directory -Path $repoTmp -Force | Out-Null
$scratch = Join-Path $repoTmp ('arrow-evaluator-' + [Guid]::NewGuid().ToString('N'))
$scratchProject = Join-Path $scratch 'project'
$hostTemp = Join-Path $scratch 'host-temp'
$skipDirectories = @('Library', 'Temp', 'Logs', 'UserSettings', 'obj', 'Obj', '.vs', '.git')

function Copy-ProjectTree([string]$Source, [string]$Destination) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($file in [IO.Directory]::EnumerateFiles($Source)) {
        $item = Get-Item -LiteralPath $file -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Candidate contains a reparse-point file: $file"
        }
        [IO.File]::Copy($file, (Join-Path $Destination $item.Name), $true)
    }
    foreach ($directory in [IO.Directory]::EnumerateDirectories($Source)) {
        $item = Get-Item -LiteralPath $directory -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Candidate contains a reparse-point directory: $directory"
        }
        if ($skipDirectories -contains $item.Name) { continue }
        Copy-ProjectTree $directory (Join-Path $Destination $item.Name)
    }
}

function Remove-TreeWithoutFollowingReparsePoints([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    $isReparsePoint =
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    $isDirectory =
        ($item.Attributes -band [IO.FileAttributes]::Directory) -ne 0
    if ($isReparsePoint) {
        if ($isDirectory) { [IO.Directory]::Delete($item.FullName, $false) }
        else { [IO.File]::Delete($item.FullName) }
        return
    }
    if (-not $isDirectory) {
        try { $item.Attributes = [IO.FileAttributes]::Normal } catch {}
        [IO.File]::Delete($item.FullName)
        return
    }
    foreach ($child in @([IO.DirectoryInfo]::new($item.FullName).GetFileSystemInfos())) {
        Remove-TreeWithoutFollowingReparsePoints $child.FullName
    }
    try { $item.Attributes = [IO.FileAttributes]::Directory } catch {}
    [IO.Directory]::Delete($item.FullName, $false)
}

function Remove-TreeRobust([string]$Path) {
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try { Remove-TreeWithoutFollowingReparsePoints $Path }
        catch {
            if ($attempt -eq 5) { throw }
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            Start-Sleep -Milliseconds (150 * $attempt)
        }
        if (-not (Test-Path -LiteralPath $Path)) { return }
    }
    if (Test-Path -LiteralPath $Path) {
        throw "Filesystem tree still exists after bounded cleanup: $Path"
    }
}

function Remove-Scratch([string]$Path) {
    $resolved = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not (Test-Under $resolved $repoTmp) -or
        -not (Split-Path -Leaf $resolved).StartsWith('arrow-evaluator-',
            [StringComparison]::Ordinal)) {
        throw "Refusing unsafe scratch cleanup: $resolved"
    }
    if (-not (Test-Path -LiteralPath $resolved)) { return }
    Assert-NoReparsePointAncestor $resolved $repoTmp
    Remove-TreeRobust $resolved
}

function Remove-OwnedInvalidOutput([string]$Path) {
    $resolved = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not (Test-Under $resolved $repoRoot) -or
        [string]::Equals($resolved, $repoRoot,
            [StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($resolved, $repoTmp,
            [StringComparison]::OrdinalIgnoreCase) -or
        (Test-Under $resolved $project)) {
        throw "Refusing unsafe invalid-output cleanup: $resolved"
    }
    if (-not (Test-Path -LiteralPath $resolved)) { return }
    $allowedRoot = if (Test-Under $resolved $repoTmp) { $repoTmp } else { $repoRuns }
    Assert-NoReparsePointAncestor $resolved $allowedRoot
    Remove-TreeRobust $resolved
}

$oldTemp = $env:TEMP
$oldTmp = $env:TMP
$exitCode = 3
$caughtError = $null
$cleanupError = $null
$hostPersistenceCleanupError = $null
$hostPersistenceScope = $null
$hostPersistenceCleanup = $null
$runnerStdout = ""
$runnerStderr = ""
try {
    New-Item -ItemType Directory -Path $scratch, $hostTemp -Force | Out-Null
    Copy-ProjectTree $project $scratchProject
    $hostPersistenceScope = New-ArrowEscapeUnityPersistenceScope `
        -ProjectPath $scratchProject
    $env:TEMP = $hostTemp
    $env:TMP = $hostTemp

    $shell = (Get-Process -Id $PID).Path
    $runner = Join-Path $PSScriptRoot 'scripts\run-evaluation.ps1'
    $arguments = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runner,
        '-ProjectPath', $scratchProject,
        '-OutputDirectory', $output,
        '-UnityCliPath', $UnityCliPath,
        '-UnityEditorPath', $UnityEditorPath
    )
    $runnerProcess = Invoke-BoundedCliProcess `
        -FilePath $shell `
        -Arguments $arguments `
        -WorkingDirectory $repoRoot `
        -TimeoutSeconds 3600 `
        -GraceSeconds 0
    $runnerExitCode = [int]$runnerProcess.exit_code
    # The public evaluator contract exposes only valid-completion 0 or invalid
    # infrastructure 3. Preserve the child code in diagnostics, but never leak
    # PowerShell/.NET platform-specific exit behavior as a candidate result.
    $exitCode = if ($runnerExitCode -eq 0) { 0 } else { 3 }
    $runnerStdout = [string]$runnerProcess.stdout
    $runnerStderr = [string]$runnerProcess.stderr
    $executionBinding = [pscustomobject]@{
        formal_engine_entry = 'unity_cli_only'
        baseline_executor = 'unity_cli_run'
        test_executor = 'unity_cli_test'
        direct_editor_fallback = $false
        unity_cli_path = (Resolve-Path -LiteralPath $UnityCliPath).Path
        unity_cli_sha256 = (Get-FileHash -LiteralPath $UnityCliPath `
            -Algorithm SHA256).Hash.ToLowerInvariant()
        unity_editor_path = (Resolve-Path -LiteralPath $UnityEditorPath).Path
        unity_editor_sha256 = (Get-FileHash -LiteralPath $UnityEditorPath `
            -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $sourceBindingAfter = Get-ArrowEscapeCurrentSourceBinding $PSScriptRoot $rulesPath
    if (-not (Test-ArrowEscapeSourceBindingEqual `
            $sourceBindingBefore $sourceBindingAfter)) {
        throw 'The canonical full Input/TOOLCHAIN/Prompt binding changed during evaluation.'
    }

    # The scratch tree is always removed, so retain one compact host-side log
    # on failure before cleanup. This captures PowerShell/runner diagnostics
    # that occur before Unity can create its own editor log.
    $hostLogPath = Join-Path $output 'evaluator-host.log'
    if ($exitCode -ne 0) {
        $hostLog = [Text.StringBuilder]::new()
        [void]$hostLog.AppendLine("Arrow Escape evaluator host diagnostic")
        [void]$hostLog.AppendLine("generated_utc=$([DateTime]::UtcNow.ToString('o'))")
        [void]$hostLog.AppendLine("public_exit_code=$exitCode")
        [void]$hostLog.AppendLine("runner_exit_code=$runnerExitCode")
        [void]$hostLog.AppendLine("argument_transport=$($runnerProcess.argument_transport)")
        if (-not [string]::IsNullOrWhiteSpace([string]$runnerProcess.launch_error)) {
            [void]$hostLog.AppendLine("launch_error=$($runnerProcess.launch_error)")
        }
        [void]$hostLog.AppendLine()
        [void]$hostLog.AppendLine('===== RUNNER STDOUT =====')
        [void]$hostLog.AppendLine($runnerStdout)
        [void]$hostLog.AppendLine()
        [void]$hostLog.AppendLine('===== RUNNER STDERR =====')
        [void]$hostLog.AppendLine($runnerStderr)
        [IO.File]::WriteAllText(
            $hostLogPath,
            $hostLog.ToString(),
            [Text.UTF8Encoding]::new($false))
    }

    if ((Test-Path -LiteralPath $output -PathType Container) -and
        -not [string]::IsNullOrWhiteSpace($runnerStdout)) {
        try {
            $runSummary = $runnerStdout | ConvertFrom-Json
            $runSummary | Add-Member -MemberType NoteProperty `
                -Name source_project_path -Value $project -Force
            $runSummary | Add-Member -MemberType NoteProperty `
                -Name evaluated_scratch_path -Value $scratchProject -Force
            $runSummary | Add-Member -MemberType NoteProperty `
                -Name execution_binding -Value $executionBinding -Force
            $runSummary | Add-Member -MemberType NoteProperty `
                -Name source_binding -Value $sourceBindingAfter -Force
            $persistenceEvidencePath = Join-Path $output `
                'unity-persistence-cleanup.json'
            if (Test-Path -LiteralPath $persistenceEvidencePath -PathType Leaf) {
                $persistenceSummary = Get-Content -Raw -Encoding UTF8 `
                    -LiteralPath $persistenceEvidencePath | ConvertFrom-Json
                $runSummary | Add-Member -MemberType NoteProperty `
                    -Name unity_persistence_cleanup `
                    -Value $persistenceSummary -Force
            }
            if (Test-Path -LiteralPath $hostLogPath -PathType Leaf) {
                $runSummary | Add-Member -MemberType NoteProperty `
                    -Name host_log -Value $hostLogPath -Force
            }
            [IO.File]::WriteAllText(
                (Join-Path $output 'run-summary.json'),
                ($runSummary | ConvertTo-Json -Depth 100),
                [Text.UTF8Encoding]::new($false))
        }
        catch {
            throw "Failed to persist evaluator run summary: $($_.Exception.Message)"
        }
    }

    foreach ($reportName in @('score.json', 'infrastructure-error.json')) {
        $reportPath = Join-Path $output $reportName
        if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { continue }
        try {
            $report = Get-Content -Raw -Encoding UTF8 -LiteralPath $reportPath |
                ConvertFrom-Json
            $report | Add-Member -MemberType NoteProperty -Name source_project_path `
                -Value $project -Force
            $report | Add-Member -MemberType NoteProperty -Name evaluated_scratch_path `
                -Value $scratchProject -Force
            $report | Add-Member -MemberType NoteProperty -Name execution_binding `
                -Value $executionBinding -Force
            if ($reportName -eq 'score.json' -and [bool]$report.valid_score -and
                -not (Test-ArrowEscapeSourceBindingEqual `
                    $report.source_binding $sourceBindingAfter)) {
                throw 'score.json is not bound to the current full Input/TOOLCHAIN/Prompt revision.'
            }
            $report | Add-Member -MemberType NoteProperty -Name source_binding `
                -Value $sourceBindingAfter -Force
            if (Test-Path -LiteralPath $hostLogPath -PathType Leaf) {
                $report | Add-Member -MemberType NoteProperty -Name host_log `
                    -Value $hostLogPath -Force
            }
            [IO.File]::WriteAllText($reportPath,
                ($report | ConvertTo-Json -Depth 100),
                [Text.UTF8Encoding]::new($false))
        }
        catch {
            throw "Failed to bind evaluator report to source project: $($_.Exception.Message)"
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($runnerStdout)) {
        $runnerStdout
    }
    if ($exitCode -ne 0 -and -not [string]::IsNullOrWhiteSpace($runnerStderr)) {
        Write-Error $runnerStderr -ErrorAction Continue
    }
}
catch {
    # Do not let a host-side exception bypass invalid-output finalization.
    # The exact invocation-owned OutputDirectory is deleted by default below.
    $caughtError = $_
    $exitCode = 3
}
finally {
    $env:TEMP = $oldTemp
    $env:TMP = $oldTmp
    if ($null -ne $hostPersistenceScope) {
        try {
            $hostPersistenceCleanup = Invoke-ArrowEscapeUnityPersistenceCleanup `
                -Scope $hostPersistenceScope `
                -Phase HostFallback `
                -Boundary Post
            if (-not [bool]$hostPersistenceCleanup.verified) {
                throw "Host fallback Unity persistence cleanup failed. " +
                    "$(@($hostPersistenceCleanup.errors) -join ' | ')"
            }
        }
        catch { $hostPersistenceCleanupError = $_ }
    }
    try { Remove-Scratch $scratch }
    catch { $cleanupError = $_ }
}

if (Test-Path -LiteralPath $output -PathType Container) {
    $hostPersistencePath = Join-Path $output `
        'host-unity-persistence-cleanup.json'
    $hostPersistenceRecord = [pscustomobject]@{
        schema_version = 1
        purpose = 'wrapper fallback after child completion, exception, or timeout'
        scope = $hostPersistenceScope
        cleanup = $hostPersistenceCleanup
        verified = $null -ne $hostPersistenceCleanup -and
            [bool]$hostPersistenceCleanup.verified
        error = if ($null -eq $hostPersistenceCleanupError) {
            $null
        } else { $hostPersistenceCleanupError.Exception.Message }
    }
    [IO.File]::WriteAllText(
        $hostPersistencePath,
        ($hostPersistenceRecord | ConvertTo-Json -Depth 20),
        [Text.UTF8Encoding]::new($false))
    foreach ($reportName in @(
            'run-summary.json', 'score.json', 'infrastructure-error.json')) {
        $reportPath = Join-Path $output $reportName
        if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { continue }
        try {
            $report = Get-Content -Raw -Encoding UTF8 -LiteralPath $reportPath |
                ConvertFrom-Json
            $report | Add-Member -MemberType NoteProperty `
                -Name host_unity_persistence_cleanup `
                -Value $hostPersistenceRecord -Force
            [IO.File]::WriteAllText(
                $reportPath,
                ($report | ConvertTo-Json -Depth 100),
                [Text.UTF8Encoding]::new($false))
        }
        catch {
            if ($null -eq $hostPersistenceCleanupError) {
                $hostPersistenceCleanupError = $_
            }
        }
    }
}

if ($null -ne $hostPersistenceCleanupError) {
    $exitCode = 3
    if ($null -eq $caughtError) { $caughtError = $hostPersistenceCleanupError }
}
if ($null -ne $cleanupError) {
    $exitCode = 3
    if ($null -eq $caughtError) { $caughtError = $cleanupError }
}
if ($null -ne $caughtError) {
    Write-Error $caughtError.Exception.Message -ErrorAction Continue
}

if ($exitCode -ne 0 -and (Test-Path -LiteralPath $output -PathType Container)) {
    if ($RetainInvalidDiagnostics) {
        $formalManifest = Join-Path $output 'run-artifact-manifest.json'
        if (Test-Path -LiteralPath $formalManifest -PathType Leaf) {
            Remove-Item -LiteralPath $formalManifest -Force
        }
        $markerPath = Join-Path $output 'AUTHOR_DIAGNOSTIC_INVALID.json'
        $marker = [pscustomobject]@{
            valid_score = $false
            author_diagnostic_only = $true
            formal_result = $false
            eligible_for_promotion = $false
            must_not_be_reported_as_score = $true
            retained_by_explicit_switch = $true
            generated_utc = [DateTime]::UtcNow.ToString('o')
            output_directory = $output
            rule = 'Never promote this directory to runs/ or cite it as a candidate score.'
        }
        [IO.File]::WriteAllText($markerPath,
            ($marker | ConvertTo-Json -Depth 5),
            [Text.UTF8Encoding]::new($false))
        Write-Warning "Retained author-only invalid diagnostics: $output"
    }
    else {
        Remove-OwnedInvalidOutput $output
        Write-Warning "Deleted invalid evaluator output: $output"
    }
}

exit $exitCode
