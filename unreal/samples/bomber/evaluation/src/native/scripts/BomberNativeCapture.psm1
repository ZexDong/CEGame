Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Save-BomberNativeCapture {
    param([string]$CaptureRoot, [string]$Name, [string]$ProcessToken, [int]$ProcessId, [int]$TimeoutMs=2500)
    if($Name -notmatch '^[A-Za-z0-9_-]{1,128}$') { throw 'measurement_fault:capture_name' }
    if(-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { throw 'candidate_capture_process_exited' }
    $readyPath=Join-Path $CaptureRoot 'ready.json'
    if(-not (Test-Path -LiteralPath $readyPath -PathType Leaf)) { throw 'measurement_fault:native_capture_plugin_not_ready' }
    $ready=Get-Content -LiteralPath $readyPath -Raw|ConvertFrom-Json
    if($ready.producer -cne 'ue-native-viewport' -or $ready.process_token -cne $ProcessToken -or $ready.process_id -ne $ProcessId) { throw 'measurement_fault:native_capture_plugin_identity' }
    $image=Join-Path $CaptureRoot "$Name.png"
    if(Test-Path -LiteralPath $image) { throw 'measurement_fault:capture_output_exists' }
    $requestId=[guid]::NewGuid().ToString('N')
    $request=[ordered]@{request_id=$requestId;name=$Name;process_token=$ProcessToken}
    $path=Join-Path $CaptureRoot 'request.json'
    [IO.File]::WriteAllText("$path.tmp",($request|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    # UE polls this file on its game thread. Windows may briefly deny replacement
    # while that reader owns the old file; retry publication within the same budget.
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($true) {
        try { [IO.File]::Move("$path.tmp",$path,$true); break }
        catch [IO.IOException] { if($watch.ElapsedMilliseconds -ge $TimeoutMs) { throw 'measurement_fault:native_request_publish_timeout' } }
        catch [UnauthorizedAccessException] { if($watch.ElapsedMilliseconds -ge $TimeoutMs) { throw 'measurement_fault:native_request_publish_timeout' } }
        Start-Sleep -Milliseconds 10
    }
    $receiptPath=Join-Path $CaptureRoot "$Name.native.json"
    do {
        if(-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { throw 'candidate_capture_process_exited' }
        if(Test-Path -LiteralPath $receiptPath -PathType Leaf) {
            $receipt=Get-Content -LiteralPath $receiptPath -Raw|ConvertFrom-Json
            if($receipt.request_id -ceq $requestId) {
                if($receipt.process_token -cne $ProcessToken -or $receipt.process_id -ne $ProcessId -or $receipt.producer -cne 'ue-native-viewport' -or $receipt.status -cne 'ok' -or $receipt.width -ne 1280 -or $receipt.height -ne 720) { throw 'measurement_fault:native_render_receipt_invalid' }
                if(-not (Test-Path -LiteralPath $image -PathType Leaf)) { throw 'measurement_fault:native_render_image_missing' }
                return [pscustomobject]@{status='ok';result=$receipt}
            }
        }
        Start-Sleep -Milliseconds 10
    } while($watch.ElapsedMilliseconds -lt $TimeoutMs)
    throw 'measurement_fault:native_render_capture_timeout'
}

Export-ModuleMember -Function Save-BomberNativeCapture
