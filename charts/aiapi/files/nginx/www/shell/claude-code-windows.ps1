$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
try {
  [Console]::OutputEncoding = [Text.Encoding]::UTF8
  $OutputEncoding = [Text.Encoding]::UTF8
} catch {
}
$ScriptSiteOrigin = if ($env:EST_SITE_ORIGIN) { $env:EST_SITE_ORIGIN } else { "__AIAPI_SITE_ORIGIN__" }
$AiapiOriginPlaceholder = "__AIAPI_SITE_" + "ORIGIN__"

if ($env:EST_AIAPI_COMMON_PS1) {
  . $env:EST_AIAPI_COMMON_PS1
} else {
  $commonSiteOrigin = $ScriptSiteOrigin
  if ([string]::IsNullOrWhiteSpace($commonSiteOrigin) -or $commonSiteOrigin -eq $AiapiOriginPlaceholder) {
    throw "Cannot detect AIAPI site. Use the /getstart/claude-code-windows installer"
  }

  $commonUrl = "$($commonSiteOrigin.TrimEnd('/'))/getstart/lib/common-windows"
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  } catch {
  }

  try {
    $commonScript = (Invoke-WebRequest -Uri $commonUrl -UseBasicParsing -ErrorAction Stop).Content
    if ([string]::IsNullOrWhiteSpace($commonScript)) {
      throw "Common script is empty"
    }

    Invoke-Expression $commonScript
  } catch {
    throw "Failed to load common script: $commonUrl. $($_.Exception.Message)"
  }
}

if (-not (Get-Command Resolve-AiapiTokenUrl -CommandType Function -ErrorAction SilentlyContinue)) {
  throw "Common script did not load correctly: Resolve-AiapiTokenUrl is missing"
}

$SiteOrigin = $ScriptSiteOrigin
$TokenUrl = Resolve-AiapiTokenUrl -SiteOrigin $SiteOrigin -TokenUrl $env:EST_TOKEN_URL
$ClaudeBaseUrl = if ($env:EST_ANTHROPIC_BASE_URL) {
  $env:EST_ANTHROPIC_BASE_URL
} elseif ($env:EST_CLAUDE_BASE_URL) {
  $env:EST_CLAUDE_BASE_URL
} else {
  ""
}
$ClaudeBaseUrl = Resolve-AiapiAnthropicBaseUrl -SiteOrigin $SiteOrigin -AnthropicBaseUrl $ClaudeBaseUrl
$Model = if ($env:EST_MODEL) { $env:EST_MODEL } else { "gpt-5.6-sol" }
$ClaudeHome = Get-AiapiHome -CurrentHome $env:EST_CLAUDE_HOME -DefaultChild ".claude" -EnvName "EST_CLAUDE_HOME"

$ApiKey = Read-AiapiApiKey -CurrentKey $env:EST_API_KEY -Url $TokenUrl -BaseUrl $ClaudeBaseUrl
Assert-AiapiApiKey $ApiKey

New-Item -ItemType Directory -Force -Path $ClaudeHome | Out-Null

$SettingsFile = Join-Path $ClaudeHome "settings.json"
$Stamp = Get-Date -Format "yyyyMMddHHmmss"
Backup-AiapiFile -Path $SettingsFile -Stamp $Stamp

if (Test-Path -LiteralPath $SettingsFile) {
  $raw = Get-Content -LiteralPath $SettingsFile -Raw -Encoding UTF8
} else {
  $raw = ""
}

if ([string]::IsNullOrWhiteSpace($raw)) {
  $settings = [pscustomobject]@{}
} else {
  $settings = $raw | ConvertFrom-Json
  if ($null -eq $settings -or $settings -is [array] -or $settings -is [string] -or $settings -is [ValueType]) {
    throw "Claude Code settings.json must be a JSON object"
  }
}

$envProperty = $settings.PSObject.Properties["env"]
$envValue = if ($null -ne $envProperty) { $envProperty.Value } else { $null }
if ($null -eq $envValue -or $envValue -is [array] -or $envValue -is [string] -or $envValue -is [ValueType]) {
  Set-AiapiJsonProperty -Object $settings -Name "env" -Value ([pscustomobject]@{})
}

Set-AiapiJsonProperty -Object $settings.env -Name "ANTHROPIC_BASE_URL" -Value $ClaudeBaseUrl
Set-AiapiJsonProperty -Object $settings.env -Name "ANTHROPIC_AUTH_TOKEN" -Value $ApiKey
Set-AiapiJsonProperty -Object $settings.env -Name "ANTHROPIC_MODEL" -Value $Model
Set-AiapiJsonProperty -Object $settings.env -Name "ANTHROPIC_SMALL_FAST_MODEL" -Value $Model
Set-AiapiJsonProperty -Object $settings.env -Name "CLAUDE_CODE_ATTRIBUTION_HEADER" -Value "0"

$json = $settings | ConvertTo-Json -Depth 20
Write-AiapiUtf8File -Path $SettingsFile -Text ($json + [Environment]::NewLine)
Save-AiapiApiKey -ApiKey $ApiKey -BaseUrl $ClaudeBaseUrl

Write-Host ""
Write-Host "AIAPI Claude Code setup completed."
Write-Host "Claude Home: $ClaudeHome"
Write-Host "Base URL: $ClaudeBaseUrl"
Write-Host "Model: $Model"
Write-Host "Restart Claude Code if it is already running."
