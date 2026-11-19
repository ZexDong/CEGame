Set-StrictMode -Version Latest
function Resolve-ActionRoguelikeD6Configuration {
    param([uri]$BaseUrl,[string]$ModelId,[string]$ConfigurationPath)
    if(-not$BaseUrl){$value=[Environment]::GetEnvironmentVariable('NEWAPI_BASE_URL');if($value){$BaseUrl=[uri]$value}}
    if(-not$ModelId){$ModelId=[Environment]::GetEnvironmentVariable('NEWAPI_MODEL_ID')}
    if((-not$BaseUrl-or-not$ModelId)-and-not[string]::IsNullOrWhiteSpace($ConfigurationPath)-and(Test-Path -LiteralPath $ConfigurationPath -PathType Leaf)){
        # Read only selected provider metadata. No config, auth, or endpoint is
        # copied to evidence; the key remains in its environment variable.
        $config=[IO.File]::ReadAllText($ConfigurationPath)
        if(-not$ModelId){$ModelId=[regex]::Match($config,'(?m)^model\s*=\s*"([^"]+)"').Groups[1].Value}
        if(-not$BaseUrl){
            $provider=[regex]::Match($config,'(?m)^model_provider\s*=\s*"([^"]+)"').Groups[1].Value
            if($provider){
                $section=[regex]::Match($config,'(?ms)^\[model_providers\.'+[regex]::Escape($provider)+'\]\s*\r?\n(.*?)(?=^\[|\z)').Groups[1].Value
                $endpoint=[regex]::Match($section,'(?m)^base_url\s*=\s*"([^"]+)"').Groups[1].Value
                if($endpoint){$BaseUrl=[uri]$endpoint}
            }
        }
    }
    if(-not$BaseUrl-or[string]::IsNullOrWhiteSpace($ModelId)){throw 'D6_CONFIGURATION_UNAVAILABLE: configure NEWAPI_BASE_URL and NEWAPI_MODEL_ID, explicit arguments, or an explicitly selected configuration file.'}
    return @{base_url=$BaseUrl;model_id=$ModelId}
}
