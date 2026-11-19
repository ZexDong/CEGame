function Complete-EvaluationInvocation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet(0, 3, 8)]
        [int]$ExitCode,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ReportJson
    )

    # Keep the JSON payload and the process result coupled at the final script
    # boundary. `exit` terminates only the invoking .ps1 when that script was
    # called with `&`, and it becomes the process exit code under `pwsh -File`.
    $null = $ReportJson | ConvertFrom-Json -ErrorAction Stop
    Write-Output $ReportJson
    exit $ExitCode
}
