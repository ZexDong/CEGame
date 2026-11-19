function ConvertFrom-ArrowEscapeUnityYamlScalar {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    $scalar = $Value.Trim()
    if ($scalar.Length -ge 2 -and $scalar[0] -eq "'" -and
        $scalar[$scalar.Length - 1] -eq "'") {
        return $scalar.Substring(1, $scalar.Length - 2).Replace("''", "'")
    }
    if ($scalar.Length -ge 2 -and $scalar[0] -eq '"' -and
        $scalar[$scalar.Length - 1] -eq '"') {
        try { return [string]($scalar | ConvertFrom-Json) }
        catch { throw "Invalid quoted Unity YAML scalar: $scalar" }
    }
    return $scalar
}

function Test-ArrowEscapeUnityIdentitySegment {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -in @('.', '..')) {
        return $false
    }
    $hasControlCharacter = @($Value.ToCharArray() | Where-Object {
        [char]::IsControl([char]$_)
    }).Count -gt 0
    if ($Value -ne $Value.Trim() -or $Value.EndsWith('.') -or
        $Value.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
        $Value.Contains('/') -or $Value.Contains('\') -or
        $hasControlCharacter) {
        return $false
    }
    $stem = ($Value.Split('.')[0]).ToUpperInvariant()
    if ($stem -in @('CON', 'PRN', 'AUX', 'NUL',
            'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
            'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9')) {
        return $false
    }
    return $true
}

function Get-ArrowEscapeCanonicalLocalLowRoot {
    $localAppData = [Environment]::GetFolderPath(
        [Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($localAppData)) {
        throw 'LocalApplicationData could not be resolved.'
    }
    return [IO.Path]::GetFullPath((Join-Path $localAppData '..\LocalLow')).TrimEnd('\', '/')
}

function New-ArrowEscapeUnityPersistenceScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [string]$SyntheticLocalLowRoot = '',
        [string]$SyntheticPlayerPrefsRoot = '',
        [switch]$AllowSyntheticRoots
    )

    $settingsPath = Join-Path $ProjectPath 'ProjectSettings\ProjectSettings.asset'
    $result = [ordered]@{
        schema_version = 1
        valid = $false
        reason = ''
        canonical_roots = -not $AllowSyntheticRoots
        project_settings_path = [IO.Path]::GetFullPath($settingsPath)
        company = $null
        product = $null
        local_low_root = $null
        local_low_company = $null
        local_low_leaf = $null
        player_prefs_root = $null
        player_prefs_company = $null
        player_prefs_key = $null
    }

    try {
        if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
            throw "Unity project is missing ProjectSettings.asset: $settingsPath"
        }
        $text = Get-Content -Raw -Encoding UTF8 -LiteralPath $settingsPath
        $companyMatches = @([regex]::Matches(
            $text, '(?m)^\s*companyName:\s*(?<v>.*?)\s*$'))
        $productMatches = @([regex]::Matches(
            $text, '(?m)^\s*productName:\s*(?<v>.*?)\s*$'))
        if ($companyMatches.Count -ne 1 -or $productMatches.Count -ne 1) {
            throw 'ProjectSettings.asset must contain exactly one companyName and one productName.'
        }
        $company = ConvertFrom-ArrowEscapeUnityYamlScalar `
            ([string]$companyMatches[0].Groups['v'].Value)
        $product = ConvertFrom-ArrowEscapeUnityYamlScalar `
            ([string]$productMatches[0].Groups['v'].Value)
        if (-not (Test-ArrowEscapeUnityIdentitySegment $company) -or
            -not (Test-ArrowEscapeUnityIdentitySegment $product)) {
            throw 'companyName/productName is not a safe exact persistence identity.'
        }

        if ($AllowSyntheticRoots) {
            if ([string]::IsNullOrWhiteSpace($SyntheticLocalLowRoot) -or
                [string]::IsNullOrWhiteSpace($SyntheticPlayerPrefsRoot)) {
                throw 'Both synthetic roots are required for a synthetic persistence scope.'
            }
            $localLowRoot = [IO.Path]::GetFullPath($SyntheticLocalLowRoot).TrimEnd('\', '/')
            $playerPrefsRoot = [IO.Path]::GetFullPath($SyntheticPlayerPrefsRoot).TrimEnd('\', '/')
        } else {
            if (-not [string]::IsNullOrWhiteSpace($SyntheticLocalLowRoot) -or
                -not [string]::IsNullOrWhiteSpace($SyntheticPlayerPrefsRoot)) {
                throw 'Synthetic persistence roots require AllowSyntheticRoots.'
            }
            $localLowRoot = Get-ArrowEscapeCanonicalLocalLowRoot
            $playerPrefsRoot = 'HKCU:\Software\Unity\UnityEditor'
        }

        $localLowCompany = [IO.Path]::GetFullPath((Join-Path $localLowRoot $company))
        $localLowLeaf = [IO.Path]::GetFullPath((Join-Path $localLowCompany $product))
        if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
                (Split-Path -Parent $localLowCompany), $localLowRoot) -or
            -not [StringComparer]::OrdinalIgnoreCase.Equals(
                (Split-Path -Parent $localLowLeaf), $localLowCompany)) {
            throw 'The LocalLow identity escaped its exact company/product scope.'
        }

        if ($AllowSyntheticRoots) {
            $playerPrefsCompany = [IO.Path]::GetFullPath(
                (Join-Path $playerPrefsRoot $company))
            $playerPrefsKey = [IO.Path]::GetFullPath(
                (Join-Path $playerPrefsCompany $product))
        } else {
            $playerPrefsCompany = "$playerPrefsRoot\$company"
            $playerPrefsKey = "$playerPrefsCompany\$product"
        }

        $result.valid = $true
        $result.company = $company
        $result.product = $product
        $result.local_low_root = $localLowRoot
        $result.local_low_company = $localLowCompany
        $result.local_low_leaf = $localLowLeaf
        $result.player_prefs_root = $playerPrefsRoot
        $result.player_prefs_company = $playerPrefsCompany
        $result.player_prefs_key = $playerPrefsKey
    }
    catch {
        $result.reason = $_.Exception.Message
    }
    return [pscustomobject]$result
}

function Get-ArrowEscapeUnityPersistenceScopeBinding {
    param([Parameter(Mandatory = $true)]$Scope)

    $payload = [ordered]@{
        schema_version = [int]$Scope.schema_version
        canonical_roots = [bool]$Scope.canonical_roots
        project_settings_path = [string]$Scope.project_settings_path
        company = [string]$Scope.company
        product = [string]$Scope.product
        local_low_root = [string]$Scope.local_low_root
        local_low_company = [string]$Scope.local_low_company
        local_low_leaf = [string]$Scope.local_low_leaf
        player_prefs_root = [string]$Scope.player_prefs_root
        player_prefs_company = [string]$Scope.player_prefs_company
        player_prefs_key = [string]$Scope.player_prefs_key
    }
    $json = $payload | ConvertTo-Json -Depth 5 -Compress
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes)) `
            -replace '-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Test-ArrowEscapeUnityPersistenceScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Scope,
        [switch]$AllowSyntheticRoots
    )

    $result = [ordered]@{
        valid = $false
        reason = ''
        local_low_leaf = $null
        player_prefs_key = $null
        registry_subkey = $null
    }
    try {
        foreach ($name in @(
                'valid', 'canonical_roots', 'company', 'product',
                'local_low_root', 'local_low_company', 'local_low_leaf',
                'player_prefs_root', 'player_prefs_company', 'player_prefs_key')) {
            if ($null -eq $Scope.PSObject.Properties[$name]) {
                throw "Persistence scope property is missing: $name"
            }
        }
        if (-not [bool]$Scope.valid) {
            throw "Persistence scope is invalid: $([string]$Scope.reason)"
        }
        $company = [string]$Scope.company
        $product = [string]$Scope.product
        if (-not (Test-ArrowEscapeUnityIdentitySegment $company) -or
            -not (Test-ArrowEscapeUnityIdentitySegment $product)) {
            throw 'Persistence identity is unsafe.'
        }

        $synthetic = -not [bool]$Scope.canonical_roots
        if ($synthetic -and -not $AllowSyntheticRoots) {
            throw 'Synthetic persistence scope is not allowed in a formal evaluation.'
        }
        if (-not $synthetic -and $AllowSyntheticRoots) {
            throw 'A canonical scope cannot be downgraded to synthetic cleanup.'
        }

        $expectedLocalRoot = if ($synthetic) {
            [IO.Path]::GetFullPath([string]$Scope.local_low_root).TrimEnd('\', '/')
        } else { Get-ArrowEscapeCanonicalLocalLowRoot }
        $expectedLocalCompany = [IO.Path]::GetFullPath(
            (Join-Path $expectedLocalRoot $company))
        $expectedLocalLeaf = [IO.Path]::GetFullPath(
            (Join-Path $expectedLocalCompany $product))
        foreach ($pair in @(
                @([string]$Scope.local_low_root, $expectedLocalRoot, 'local_low_root'),
                @([string]$Scope.local_low_company, $expectedLocalCompany, 'local_low_company'),
                @([string]$Scope.local_low_leaf, $expectedLocalLeaf, 'local_low_leaf'))) {
            $provided = [IO.Path]::GetFullPath([string]$pair[0]).TrimEnd('\', '/')
            $expected = [IO.Path]::GetFullPath([string]$pair[1]).TrimEnd('\', '/')
            if (-not [StringComparer]::OrdinalIgnoreCase.Equals($provided, $expected)) {
                throw "$([string]$pair[2]) escaped the exact company/product scope."
            }
        }
        if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
                (Split-Path -Parent $expectedLocalCompany), $expectedLocalRoot) -or
            -not [StringComparer]::OrdinalIgnoreCase.Equals(
                (Split-Path -Parent $expectedLocalLeaf), $expectedLocalCompany)) {
            throw 'LocalLow scope does not have exactly company/product depth.'
        }

        if ($synthetic) {
            $expectedPrefsRoot = [IO.Path]::GetFullPath(
                [string]$Scope.player_prefs_root).TrimEnd('\', '/')
            $expectedPrefsCompany = [IO.Path]::GetFullPath(
                (Join-Path $expectedPrefsRoot $company))
            $expectedPrefsKey = [IO.Path]::GetFullPath(
                (Join-Path $expectedPrefsCompany $product))
            foreach ($pair in @(
                    @([string]$Scope.player_prefs_root, $expectedPrefsRoot, 'player_prefs_root'),
                    @([string]$Scope.player_prefs_company, $expectedPrefsCompany, 'player_prefs_company'),
                    @([string]$Scope.player_prefs_key, $expectedPrefsKey, 'player_prefs_key'))) {
                $provided = [IO.Path]::GetFullPath([string]$pair[0]).TrimEnd('\', '/')
                $expected = [IO.Path]::GetFullPath([string]$pair[1]).TrimEnd('\', '/')
                if (-not [StringComparer]::OrdinalIgnoreCase.Equals($provided, $expected)) {
                    throw "$([string]$pair[2]) escaped the exact company/product scope."
                }
            }
            if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
                    (Split-Path -Parent $expectedPrefsCompany), $expectedPrefsRoot) -or
                -not [StringComparer]::OrdinalIgnoreCase.Equals(
                    (Split-Path -Parent $expectedPrefsKey), $expectedPrefsCompany)) {
                throw 'Synthetic PlayerPrefs scope does not have exactly company/product depth.'
            }
            $result.player_prefs_key = $expectedPrefsKey
        } else {
            $expectedPrefsRoot = 'HKCU:\Software\Unity\UnityEditor'
            $expectedPrefsCompany = "$expectedPrefsRoot\$company"
            $expectedPrefsKey = "$expectedPrefsCompany\$product"
            foreach ($pair in @(
                    @([string]$Scope.player_prefs_root, $expectedPrefsRoot, 'player_prefs_root'),
                    @([string]$Scope.player_prefs_company, $expectedPrefsCompany, 'player_prefs_company'),
                    @([string]$Scope.player_prefs_key, $expectedPrefsKey, 'player_prefs_key'))) {
                if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
                        [string]$pair[0], [string]$pair[1])) {
                    throw "$([string]$pair[2]) escaped the exact company/product scope."
                }
            }
            $result.player_prefs_key = $expectedPrefsKey
            $result.registry_subkey = "Software\Unity\UnityEditor\$company\$product"
        }

        $result.valid = $true
        $result.local_low_leaf = $expectedLocalLeaf
    }
    catch {
        $result.reason = $_.Exception.Message
    }
    return [pscustomobject]$result
}

function Remove-ArrowEscapeFileSystemTreeNoFollow {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    $isDirectory = ($item.Attributes -band [IO.FileAttributes]::Directory) -ne 0
    $isReparsePoint = ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
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
        Remove-ArrowEscapeFileSystemTreeNoFollow $child.FullName
    }
    try { $item.Attributes = [IO.FileAttributes]::Directory } catch {}
    [IO.Directory]::Delete($item.FullName, $false)
}

function Test-ArrowEscapeRegistrySubKeyExists {
    param([Parameter(Mandatory = $true)][string]$SubKey)

    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($SubKey, $false)
    try { return $null -ne $key }
    finally { if ($null -ne $key) { $key.Dispose() } }
}

function Invoke-ArrowEscapeUnityPersistenceCleanup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Scope,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Baseline', 'Static', 'Dynamic', 'Fresh', 'HostFallback')]
        [string]$Phase,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Pre', 'Post')]
        [string]$Boundary,
        [ValidateRange(1, 10)][int]$MaximumAttempts = 5,
        [switch]$AllowSyntheticRoots
    )

    $started = [DateTime]::UtcNow
    $scopeCheck = Test-ArrowEscapeUnityPersistenceScope `
        -Scope $Scope -AllowSyntheticRoots:$AllowSyntheticRoots
    $result = [ordered]@{
        schema_version = 1
        phase = $Phase
        boundary = $Boundary
        started_utc = $started.ToString('o')
        completed_utc = $null
        scope_valid = [bool]$scopeCheck.valid
        scope_error = [string]$scopeCheck.reason
        company = if ($null -eq $Scope.PSObject.Properties['company']) { $null } else { [string]$Scope.company }
        product = if ($null -eq $Scope.PSObject.Properties['product']) { $null } else { [string]$Scope.product }
        local_low_leaf = [string]$scopeCheck.local_low_leaf
        player_prefs_key = [string]$scopeCheck.player_prefs_key
        scope_binding_sha256 = if ([bool]$scopeCheck.valid) {
            Get-ArrowEscapeUnityPersistenceScopeBinding $Scope
        } else { $null }
        local_low_existed_before = $null
        player_prefs_existed_before = $null
        removed_local_low = $false
        removed_player_prefs = $false
        attempt_count = 0
        retry_errors = @()
        local_low_absent_after = $false
        player_prefs_absent_after = $false
        verified = $false
        errors = @()
    }
    if (-not [bool]$scopeCheck.valid) {
        $result.errors = @([string]$scopeCheck.reason)
        $result.completed_utc = [DateTime]::UtcNow.ToString('o')
        return [pscustomobject]$result
    }

    $synthetic = -not [bool]$Scope.canonical_roots
    $leaf = [string]$scopeCheck.local_low_leaf
    $prefs = [string]$scopeCheck.player_prefs_key
    $registrySubKey = [string]$scopeCheck.registry_subkey
    try {
        $result.local_low_existed_before = Test-Path -LiteralPath $leaf
        $result.player_prefs_existed_before = if ($synthetic) {
            Test-Path -LiteralPath $prefs
        } else { Test-ArrowEscapeRegistrySubKeyExists $registrySubKey }

        $retryErrors = [System.Collections.Generic.List[string]]::new()
        for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
            $result.attempt_count = $attempt
            try {
                if (Test-Path -LiteralPath $leaf) {
                    Remove-ArrowEscapeFileSystemTreeNoFollow $leaf
                    $result.removed_local_low = $true
                }
                if ($synthetic) {
                    if (Test-Path -LiteralPath $prefs) {
                        Remove-ArrowEscapeFileSystemTreeNoFollow $prefs
                        $result.removed_player_prefs = $true
                    }
                } elseif (Test-ArrowEscapeRegistrySubKeyExists $registrySubKey) {
                    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree(
                        $registrySubKey, $false)
                    $result.removed_player_prefs = $true
                }
            }
            catch {
                $retryErrors.Add("attempt_${attempt}:$($_.Exception.Message)")
            }

            $result.local_low_absent_after = -not (Test-Path -LiteralPath $leaf)
            $result.player_prefs_absent_after = if ($synthetic) {
                -not (Test-Path -LiteralPath $prefs)
            } else { -not (Test-ArrowEscapeRegistrySubKeyExists $registrySubKey) }
            if ($result.local_low_absent_after -and
                $result.player_prefs_absent_after) {
                $result.verified = $true
                break
            }
            if ($attempt -lt $MaximumAttempts) {
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
                Start-Sleep -Milliseconds (100 * $attempt)
            }
        }
        $result.retry_errors = @($retryErrors)
        if (-not $result.verified) {
            $result.errors = @('Exact LocalLow leaf or PlayerPrefs key remained after bounded cleanup.')
        }
    }
    catch {
        $result.errors = @($_.Exception.Message)
    }
    $result.completed_utc = [DateTime]::UtcNow.ToString('o')
    return [pscustomobject]$result
}
