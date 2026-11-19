Set-StrictMode -Version Latest

function ConvertTo-WindowsNativeArgument([string]$Value) {
    if ($null -eq $Value) { $Value = "" }
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
        return $Value
    }

    # CommandLineToArgvW-compatible fallback for Windows PowerShell/.NET
    # Framework, where ProcessStartInfo.ArgumentList is unavailable.
    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq [char]92) {
            $backslashes++
            continue
        }
        if ($character -eq [char]34) {
            if ($backslashes -gt 0) {
                [void]$builder.Append(('\' * ($backslashes * 2) -join ''))
            }
            [void]$builder.Append('\"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append(('\' * $backslashes -join ''))
            $backslashes = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) {
        [void]$builder.Append(('\' * ($backslashes * 2) -join ''))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Invoke-BoundedCliProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 3600)]
        [int]$TimeoutSeconds,

        [ValidateRange(0, 300)]
        [int]$GraceSeconds = 45
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    if ($null -ne $startInfo.PSObject.Properties['ArgumentList']) {
        foreach ($argument in @($Arguments)) {
            $startInfo.ArgumentList.Add([string]$argument)
        }
    } else {
        $startInfo.Arguments = (@($Arguments | ForEach-Object {
            ConvertTo-WindowsNativeArgument ([string]$_)
        }) -join ' ')
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $stdoutTask = $null
    $stderrTask = $null
    $processId = 0
    $exitCode = -1
    $timedOut = $false
    $launchError = ""
    $stdout = ""
    $stderr = ""
    try {
        if (-not $process.Start()) {
            throw "Process.Start returned false for $FilePath."
        }
        $processId = [int]$process.Id
        # Drain both redirected pipes asynchronously from process start. This
        # avoids deadlock and, unlike Start-Process file redirection, gives us
        # ownership of the stream lifetime so it is closed before diagnostics
        # are written or the disposable project is removed.
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit(($TimeoutSeconds + $GraceSeconds) * 1000)) {
            $timedOut = $true
            try {
                $killTree = $process.GetType().GetMethod('Kill', [Type[]]@([bool]))
                if ($null -ne $killTree) {
                    [void]$killTree.Invoke($process, @($true))
                } else {
                    $process.Kill()
                }
            }
            catch {
                try { $process.Kill() } catch {}
            }
            [void]$process.WaitForExit(10000)
            $exitCode = 124
        } else {
            $process.WaitForExit()
            $exitCode = [int]$process.ExitCode
            if ($exitCode -eq 124) { $timedOut = $true }
        }

        if ($null -ne $stdoutTask) {
            $stdout = [string]$stdoutTask.GetAwaiter().GetResult()
        }
        if ($null -ne $stderrTask) {
            $stderr = [string]$stderrTask.GetAwaiter().GetResult()
        }
    }
    catch {
        $launchError = $_.Exception.ToString()
        try {
            if ($null -ne $stdoutTask) {
                $stdout = [string]$stdoutTask.GetAwaiter().GetResult()
            }
        } catch {}
        try {
            if ($null -ne $stderrTask) {
                $stderr = [string]$stderrTask.GetAwaiter().GetResult()
            }
        } catch {}
    }
    finally {
        $process.Dispose()
    }

    return [pscustomobject]@{
        process_id = $processId
        exit_code = $exitCode
        timed_out = $timedOut
        stdout = $stdout
        stderr = $stderr
        launch_error = $launchError
        argument_transport = if (
            $null -ne $startInfo.PSObject.Properties['ArgumentList']) {
            'ProcessStartInfo.ArgumentList'
        } else {
            'ProcessStartInfo.Arguments(CommandLineToArgvW quoting)'
        }
    }
}
