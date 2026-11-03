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
    throw "Cannot detect AIAPI site. Use the /getstart/codex-windows installer"
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
$ApiBaseUrl = Resolve-AiapiOpenAiBaseUrl -SiteOrigin $SiteOrigin -ApiBaseUrl $env:EST_API_BASE_URL
$ApiBaseUrl = $ApiBaseUrl.TrimEnd('/')
if ($ApiBaseUrl -match '/codex$') {
  $ApiBaseUrl = $ApiBaseUrl.Substring(0, $ApiBaseUrl.Length - 6)
}
$CatalogUrl = "$ApiBaseUrl/codex/models"
$ProviderId = if ($env:EST_PROVIDER_ID) { $env:EST_PROVIDER_ID } else { "eshetang" }
$LegacyProviderId = if ($env:EST_LEGACY_PROVIDER_ID) { $env:EST_LEGACY_PROVIDER_ID } else { $ProviderId }
$LegacyProfile = if ($env:EST_LEGACY_PROFILE) { $env:EST_LEGACY_PROFILE } elseif ($env:EST_PROFILE) { $env:EST_PROFILE } else { "third_party" }
$Model = if ($env:EST_MODEL) { $env:EST_MODEL } else { "gpt-6.1-sol" }
$WireApi = if ($env:EST_WIRE_API) { $env:EST_WIRE_API } else { "responses" }
$CodexHome = Get-AiapiHome -CurrentHome $env:EST_CODEX_HOME -DefaultChild ".codex" -EnvName "EST_CODEX_HOME"

Assert-AiapiTomlKey "EST_PROVIDER_ID" $ProviderId

$ApiKey = Read-AiapiApiKey -CurrentKey $env:EST_API_KEY -Url $TokenUrl -BaseUrl $ApiBaseUrl
Assert-AiapiApiKey $ApiKey

New-Item -ItemType Directory -Force -Path $CodexHome | Out-Null

$ConfigFile = Join-Path $CodexHome "config.toml"
$CatalogFile = Join-Path $CodexHome "aiapi-models.json"
$CatalogTemp = Join-Path $CodexHome ("aiapi-models.json.tmp." + [Guid]::NewGuid().ToString("N"))
$Stamp = Get-Date -Format "yyyyMMddHHmmss"
$UseModelCatalog = $false
$ManagedRootKeys = @("model", "model_provider", "openai_base_url", "profile", "web_search")

$headers = @{ Authorization = "Bearer $ApiKey" }
Write-Host "正在获取三方模型..."
try {
  Invoke-WebRequest -Uri $CatalogUrl -Headers $headers -UseBasicParsing -OutFile $CatalogTemp
  $catalog = Get-Content -LiteralPath $CatalogTemp -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($null -eq $catalog -or $catalog.models -isnot [array]) {
    throw "Invalid model catalog: expected a models array"
  }
  $thirdPartyModels = @($catalog.models | Where-Object {
    $slug = [string]$_.slug
    -not [string]::IsNullOrWhiteSpace($slug) -and (($slug -split '/')[-1] -notmatch 'gpt')
  })

  if ($thirdPartyModels.Count -eq 0) {
    Write-Host "未获取到非 GPT 系列模型，已跳过模型目录配置。"
  } else {
    Backup-AiapiFile -Path $CatalogFile -Stamp $Stamp
    Move-Item -LiteralPath $CatalogTemp -Destination $CatalogFile -Force
    $UseModelCatalog = $true
  }
  $ManagedRootKeys += "model_catalog_json"
} catch {
  Write-Warning "获取三方模型失败，已保留原有模型目录配置。错误类型：$($_.Exception.GetType().Name)"
} finally {
  if (Test-Path -LiteralPath $CatalogTemp) {
    Remove-Item -LiteralPath $CatalogTemp -Force
  }
}

if (Test-Path -LiteralPath $ConfigFile) {
  $existingLines = @(Get-Content -LiteralPath $ConfigFile -Encoding UTF8)
} else {
  $existingLines = @()
}

$filteredLines = @(Merge-AiapiTomlTable `
  -Lines $existingLines `
  -RootKeys $ManagedRootKeys `
  -RemoveTables @("profiles.$LegacyProfile", "model_providers.$ProviderId", "model_providers.$LegacyProviderId") `
  -Table "agents" `
  -ManagedLines @("max_concurrent_threads_per_session = 12"))
$filteredLines = @(Merge-AiapiTomlTable `
  -Lines $filteredLines `
  -RootKeys @() `
  -RemoveTables @() `
  -Table "features" `
  -ManagedLines @("remote_compaction_v2 = true", "multi_agent_v2 = true"))
$configLines = @(
  "model = `"$(Escape-AiapiTomlString $Model)`"",
  "model_provider = `"$(Escape-AiapiTomlString $ProviderId)`""
)
if ($UseModelCatalog) {
  $configLines += "model_catalog_json = `"$(Escape-AiapiTomlString $CatalogFile)`""
}
$configLines += @(
  "web_search = `"live`"",
  ""
)

if ($filteredLines.Count -gt 0) {
  $firstContentIndex = 0
  while ($firstContentIndex -lt $filteredLines.Count -and [string]::IsNullOrWhiteSpace($filteredLines[$firstContentIndex])) {
    $firstContentIndex++
  }

  if ($firstContentIndex -lt $filteredLines.Count) {
    $configLines += $filteredLines[$firstContentIndex..($filteredLines.Count - 1)]
    $configLines += ""
  }
}

$configLines += @(
  "[model_providers.$ProviderId]",
  "name = `"OpenAI`"",
  "base_url = `"$(Escape-AiapiTomlString $ApiBaseUrl)`"",
  "wire_api = `"$(Escape-AiapiTomlString $WireApi)`"",
  "requires_openai_auth = true",
  "supports_websockets = true",
  "supports_standalone_web_search = true",
  "experimental_bearer_token = `"$(Escape-AiapiTomlString $ApiKey)`""
)

Backup-AiapiFile -Path $ConfigFile -Stamp $Stamp
Write-AiapiUtf8File -Path $ConfigFile -Text (($configLines -join [Environment]::NewLine) + [Environment]::NewLine)
Save-AiapiApiKey -ApiKey $ApiKey -BaseUrl $ApiBaseUrl

Write-Host ""
Write-Host "AIAPI Codex setup completed."
Write-Host "Codex Home: $CodexHome"
Write-Host "Provider: $ProviderId"
Write-Host "Base URL: $ApiBaseUrl"
if ($UseModelCatalog) {
  Write-Host "Model Catalog: $CatalogFile"
}
Write-Host "Model: $Model"
Write-Host "Restart Codex if it is already running."
