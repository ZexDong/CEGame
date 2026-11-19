function Get-ArrowEscapeSha256([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or
        -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required source-binding file is missing: $Path"
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ArrowEscapeCompleteTreeBinding([string]$BasePath) {
    $root = (Resolve-Path -LiteralPath $BasePath).Path.TrimEnd('\', '/')
    $records = [System.Collections.Generic.List[string]]::new()
    $fileCount = 0
    $directoryCount = 0

    foreach ($entry in @(Get-ChildItem -LiteralPath $root -Recurse -Force)) {
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Source binding cannot traverse a reparse point: $($entry.FullName)"
        }
        $relative = $entry.FullName.Substring($root.Length).TrimStart('\', '/') `
            -replace '\\', '/'
        if ($entry.PSIsContainer) {
            $directoryCount++
            $records.Add("D|$relative")
        } else {
            $fileCount++
            $hash = Get-ArrowEscapeSha256 $entry.FullName
            $records.Add("F|$relative|$($entry.Length)|$hash")
        }
    }

    $ordered = $records.ToArray()
    [Array]::Sort($ordered, [StringComparer]::Ordinal)
    $bytes = [Text.Encoding]::UTF8.GetBytes(($ordered -join "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $treeHash = ([BitConverter]::ToString($sha.ComputeHash($bytes)) `
            -replace '-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }

    return [pscustomobject]@{
        file_count = $fileCount
        directory_count = $directoryCount
        sha256 = $treeHash
        algorithm = "sha256(utf8(join(sorted(D|path,F|path|bytes|sha256), LF)))"
    }
}

function Get-ArrowEscapeFileSetBinding(
    [string]$BasePath,
    [object[]]$Files,
    [string]$Scope
) {
    $root = (Resolve-Path -LiteralPath $BasePath).Path.TrimEnd('\', '/')
    $records = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)

    foreach ($fileValue in @($Files)) {
        if ($null -eq $fileValue) { continue }
        $candidate = if ($fileValue -is [IO.FileSystemInfo]) {
            [string]$fileValue.FullName
        } else {
            [string]$fileValue
        }
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $full = [IO.Path]::GetFullPath($candidate)
        if (-not ($full.StartsWith($root + '\',
                    [StringComparison]::OrdinalIgnoreCase))) {
            throw "Evaluator binding file escaped its root: $full"
        }
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            throw "Evaluator binding file is missing: $full"
        }
        $item = Get-Item -LiteralPath $full -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Evaluator binding cannot include a reparse point: $full"
        }
        $relative = $full.Substring($root.Length).TrimStart('\', '/') `
            -replace '\\', '/'
        if (-not $seen.Add($relative)) { continue }
        $records.Add("$relative`t$(Get-ArrowEscapeSha256 $full)")
    }

    $ordered = $records.ToArray()
    [Array]::Sort($ordered, [StringComparer]::Ordinal)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($ordered -join "`n"))
        $bindingHash = ([BitConverter]::ToString($sha.ComputeHash($bytes)) `
            -replace '-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
    return [pscustomobject]@{
        scope = $Scope
        file_count = $ordered.Count
        sha256 = $bindingHash
        algorithm = 'sha256(utf8(join(ordinal-sorted(relative-path + TAB + file-sha256), LF)))'
    }
}

function Get-ArrowEscapeEvaluatorReleaseBinding([string]$EvaluationRoot) {
    $root = (Resolve-Path -LiteralPath $EvaluationRoot).Path.TrimEnd('\', '/')
    $files = [System.Collections.Generic.List[object]]::new()
    foreach ($relative in @(
            'README.md',
            'evaluate.ps1',
            'rules.json',
            'requirement-coverage.json')) {
        $files.Add((Get-Item -LiteralPath (Join-Path $root $relative) -Force))
    }
    foreach ($relativeDirectory in @('package', 'scripts', 'tests', 'visual')) {
        foreach ($file in @(Get-ChildItem -LiteralPath (
                    Join-Path $root $relativeDirectory) -Recurse -File -Force)) {
            $files.Add($file)
        }
    }
    Get-ArrowEscapeFileSetBinding -BasePath $root -Files @($files) `
        -Scope ('README.md + evaluate.ps1 + rules.json + requirement-coverage.json + ' +
            'package/** + scripts/** + tests/** + visual/**; excludes reference/**, ' +
            'author-reference-assets/**, equivalent-correct-project/** and ' +
            'equivalent-direct-polling-project/**')
}

function Get-ArrowEscapeEvaluatorReleaseBindings([string]$EvaluationRoot) {
    $root = (Resolve-Path -LiteralPath $EvaluationRoot).Path.TrimEnd('\', '/')
    $functionalFiles = [System.Collections.Generic.List[object]]::new()
    foreach ($relative in @('rules.json', 'requirement-coverage.json')) {
        $functionalFiles.Add((Get-Item -LiteralPath (
                    Join-Path $root $relative) -Force))
    }
    foreach ($relativeDirectory in @('package', 'scripts', 'visual')) {
        foreach ($file in @(Get-ChildItem -LiteralPath (
                    Join-Path $root $relativeDirectory) -Recurse -File -Force)) {
            $functionalFiles.Add($file)
        }
    }
    $functional = Get-ArrowEscapeFileSetBinding -BasePath $root `
        -Files @($functionalFiles) `
        -Scope ('rules.json + requirement-coverage.json + package/** + scripts/** + ' +
            'visual/**; excludes README.md, evaluate.ps1, tests/**, reference/**, ' +
            'author-reference-assets/** and equivalent project fixtures')

    $gateFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'tests') `
        -Recurse -File -Force)
    $gate = Get-ArrowEscapeFileSetBinding -BasePath $root -Files $gateFiles `
        -Scope 'tests/** PowerShell evaluator regression and self-test gates'

    $definitionsDirectory = Join-Path $root `
        'package\Tests\Dynamic\Resources\TrajectoryDefinitions'
    $trajectoryFiles = @(Get-ChildItem -LiteralPath $definitionsDirectory `
        -File -Filter '*.json' -Force)
    $trajectory = Get-ArrowEscapeFileSetBinding -BasePath $root `
        -Files $trajectoryFiles `
        -Scope 'package/Tests/Dynamic/Resources/TrajectoryDefinitions/*.json'

    return [pscustomobject]@{
        evaluator = Get-ArrowEscapeEvaluatorReleaseBinding $root
        functional_evaluator = $functional
        gate_bundle = $gate
        trajectory_definitions = $trajectory
    }
}

function Get-ArrowEscapeCurrentSourceBinding(
    [string]$EvaluationRoot,
    [string]$RulesPath
) {
    $demoRoot = Split-Path -Parent $EvaluationRoot
    $inputRoot = (Resolve-Path -LiteralPath (Join-Path $demoRoot "input")).Path
    $gddPath = Join-Path $inputRoot "GDD.md"
    $toolchainPath = Join-Path $inputRoot "TOOLCHAIN.md"
    $promptPath = Join-Path $inputRoot "INITIAL_AGENT_PROMPT.md"
    $coveragePath = Join-Path $EvaluationRoot 'requirement-coverage.json'
    $contractPath = Join-Path $inputRoot `
        "Packages\com.omnigame.benchmark.arrow-escape.contracts\README.md"
    $tree = Get-ArrowEscapeCompleteTreeBinding $inputRoot

    return [pscustomobject]@{
        schema_version = 1
        input_path = $inputRoot
        input_file_count = [int]$tree.file_count
        input_directory_count = [int]$tree.directory_count
        input_tree_sha256 = [string]$tree.sha256
        input_tree_algorithm = [string]$tree.algorithm
        gdd_path = $gddPath
        gdd_sha256 = Get-ArrowEscapeSha256 $gddPath
        toolchain_path = $toolchainPath
        toolchain_sha256 = Get-ArrowEscapeSha256 $toolchainPath
        initial_agent_prompt_path = $promptPath
        initial_agent_prompt_sha256 = Get-ArrowEscapeSha256 $promptPath
        public_contract_path = $contractPath
        public_contract_sha256 = Get-ArrowEscapeSha256 $contractPath
        rules_path = $RulesPath
        rules_sha256 = Get-ArrowEscapeSha256 $RulesPath
        requirement_coverage_path = $coveragePath
        requirement_coverage_sha256 = Get-ArrowEscapeSha256 $coveragePath
    }
}

function Test-ArrowEscapeFileSetBindingEqual($Left, $Right) {
    if ($null -eq $Left -or $null -eq $Right) { return $false }
    foreach ($property in @('file_count', 'sha256')) {
        $leftProperty = $Left.PSObject.Properties[$property]
        $rightProperty = $Right.PSObject.Properties[$property]
        if ($null -eq $leftProperty -or $null -eq $rightProperty -or
            -not [string]::Equals([string]$leftProperty.Value,
                [string]$rightProperty.Value,
                [StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }
    return $true
}

function Test-ArrowEscapeTreeBindingEqual($Left, $Right) {
    if ($null -eq $Left -or $null -eq $Right) { return $false }
    foreach ($property in @('file_count', 'directory_count', 'sha256')) {
        $leftProperty = $Left.PSObject.Properties[$property]
        $rightProperty = $Right.PSObject.Properties[$property]
        if ($null -eq $leftProperty -or $null -eq $rightProperty -or
            -not [string]::Equals([string]$leftProperty.Value,
                [string]$rightProperty.Value,
                [StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }
    return $true
}

function Test-ArrowEscapeSourceBindingEqual($Left, $Right) {
    if ($null -eq $Left -or $null -eq $Right) { return $false }
    foreach ($property in @(
        "input_file_count",
        "input_directory_count",
        "input_tree_sha256",
        "gdd_sha256",
        "toolchain_sha256",
        "initial_agent_prompt_sha256",
        "public_contract_sha256",
        "rules_sha256",
        "requirement_coverage_sha256"
    )) {
        $leftProperty = $Left.PSObject.Properties[$property]
        $rightProperty = $Right.PSObject.Properties[$property]
        if ($null -eq $leftProperty -or $null -eq $rightProperty -or
            -not [string]::Equals([string]$leftProperty.Value,
                [string]$rightProperty.Value,
                [StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }
    return $true
}
