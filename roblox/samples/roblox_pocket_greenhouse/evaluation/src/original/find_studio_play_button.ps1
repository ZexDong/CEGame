param([Parameter(Mandatory=$true)][Int64]$Hwnd)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Hwnd)
if ($null -eq $root) { exit 2 }
$all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
$matches = @()
foreach ($item in $all) {
    try {
        $name = [string]$item.Current.Name
        $aid = [string]$item.Current.AutomationId
        $kind = [string]$item.Current.ControlType.ProgrammaticName
        $rect = $item.Current.BoundingRectangle
        if ($rect.IsEmpty -or $item.Current.IsOffscreen) { continue }
        if ($kind -notmatch 'Button|MenuItem') { continue }
        $exact = $name -match '^(Play|Play|Play)$'
        $semantic = ($name + ' ' + $aid) -match '(?i)(play|startplay|playtest|Play|Play)'
        if (-not ($exact -or $semantic)) { continue }
        $matches += [pscustomobject]@{priority=$(if($exact){0}else{1});top=[double]$rect.Top;left=[double]$rect.Left;width=[double]$rect.Width;height=[double]$rect.Height;name=$name;automation_id=$aid}
    } catch {}
}
$best = $matches | Sort-Object priority,top,left | Select-Object -First 1
if ($null -eq $best) { exit 3 }
$best | ConvertTo-Json -Compress
