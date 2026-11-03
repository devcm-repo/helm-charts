function Assert-AiapiTomlKey {
  param([string]$Name, [string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value) -or $Value -notmatch '^[A-Za-z0-9_]+$') {
    throw "$Name may only contain letters, numbers, and underscores"
  }
}

function Assert-AiapiApiKey {
  param([string]$ApiKey)

  if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw "EST_API_KEY is required"
  }
  if ($ApiKey -match "[`r`n]") {
    throw "EST_API_KEY must not contain newlines"
  }
}

function Escape-AiapiTomlString {
  param([string]$Value)

  return $Value.Replace('\', '\\').Replace('"', '\"')
}

function Backup-AiapiFile {
  param([string]$Path, [string]$Stamp)

  if (Test-Path -LiteralPath $Path) {
    Copy-Item -LiteralPath $Path -Destination "$Path.bak.$Stamp" -Force
  }
}

function Write-AiapiUtf8File {
  param([string]$Path, [string]$Text)

  $encoding = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Resolve-AiapiTokenUrl {
  param([string]$SiteOrigin, [string]$TokenUrl)

  if (-not [string]::IsNullOrWhiteSpace($TokenUrl)) {
    return $TokenUrl
  }
  if (-not [string]::IsNullOrWhiteSpace($SiteOrigin)) {
    return "$($SiteOrigin.TrimEnd('/'))/keys"
  }

  return ""
}

function Resolve-AiapiOpenAiBaseUrl {
  param([string]$SiteOrigin, [string]$ApiBaseUrl)

  if (-not [string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
    return $ApiBaseUrl
  }
  if ([string]::IsNullOrWhiteSpace($SiteOrigin)) {
    throw "Cannot determine AIAPI site. Use the install command from the docs, or set EST_API_BASE_URL"
  }

  return "$($SiteOrigin.TrimEnd('/'))/v1"
}

function Resolve-AiapiAnthropicBaseUrl {
  param([string]$SiteOrigin, [string]$AnthropicBaseUrl)

  if (-not [string]::IsNullOrWhiteSpace($AnthropicBaseUrl)) {
    return $AnthropicBaseUrl
  }
  if ([string]::IsNullOrWhiteSpace($SiteOrigin)) {
    throw "Cannot determine AIAPI site. Use the install command from the docs, or set EST_ANTHROPIC_BASE_URL"
  }

  return $SiteOrigin.TrimEnd('/')
}

function Read-AiapiApiKey {
  param([string]$CurrentKey, [string]$Url, [string]$BaseUrl)

  if (-not [string]::IsNullOrWhiteSpace($CurrentKey)) {
    return $CurrentKey
  }

  $PreviousKey = ""
  $cacheFile = Join-Path (Join-Path $HOME ".aiapi") "credentials"
  $origin = ([Uri]$BaseUrl).GetLeftPart([System.UriPartial]::Authority)
  if (Test-Path -LiteralPath $cacheFile -PathType Leaf) {
    $cached = [System.IO.File]::ReadAllLines($cacheFile)
    if ($cached.Length -eq 2 -and $cached[0] -ceq $origin) {
      $PreviousKey = $cached[1]
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($Url)) {
    Write-Host "AIAPI API Key URL: $Url"
  } else {
    Write-Host "AIAPI API Key URL: current AIAPI console /keys"
  }

  if (-not [string]::IsNullOrWhiteSpace($PreviousKey)) {
    Write-Host "已检测到原 API Key；不更改请直接回车，默认使用原 key。"
  }
  $secure = Read-Host "Enter EST_API_KEY" -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    $key = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    if ([string]::IsNullOrEmpty($key)) {
      return $PreviousKey
    }
    return $key
  }
  finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
}

function Save-AiapiApiKey {
  param([string]$ApiKey, [string]$BaseUrl)

  $cacheDir = Join-Path $HOME ".aiapi"
  New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
  $acl = New-Object System.Security.AccessControl.DirectorySecurity
  $acl.SetAccessRuleProtection($true, $false)
  $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
  $rule = New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList @(
    $identity, "FullControl", "ContainerInherit, ObjectInherit", "None", "Allow"
  )
  $acl.AddAccessRule($rule)
  Set-Acl -LiteralPath $cacheDir -AclObject $acl

  $cacheFile = Join-Path $cacheDir "credentials"
  $cacheTemp = Join-Path $cacheDir ("credentials.tmp." + [Guid]::NewGuid().ToString("N"))
  $origin = ([Uri]$BaseUrl).GetLeftPart([System.UriPartial]::Authority)
  try {
    Write-AiapiUtf8File -Path $cacheTemp -Text "$origin`n$ApiKey`n"
    Move-Item -LiteralPath $cacheTemp -Destination $cacheFile -Force
  } finally {
    if (Test-Path -LiteralPath $cacheTemp) {
      Remove-Item -LiteralPath $cacheTemp -Force
    }
  }
}

function Get-AiapiHome {
  param([string]$CurrentHome, [string]$DefaultChild, [string]$EnvName)

  if (-not [string]::IsNullOrWhiteSpace($CurrentHome)) {
    return $CurrentHome
  }
  if ([string]::IsNullOrWhiteSpace($HOME)) {
    throw "HOME was not found. Set $EnvName"
  }

  return Join-Path $HOME $DefaultChild
}

function Set-AiapiJsonProperty {
  param(
    [Parameter(Mandatory = $true)]$Object,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)]$Value
  )

  if ($Object.PSObject.Properties.Name -contains $Name) {
    $Object.$Name = $Value
  } else {
    Add-Member -InputObject $Object -NotePropertyName $Name -NotePropertyValue $Value
  }
}

function Merge-AiapiTomlTable {
  param(
    [string[]]$Lines,
    [string[]]$RootKeys,
    [string[]]$RemoveTables,
    [string]$Table,
    [string[]]$ManagedLines
  )

  $result = @()
  $mergedLines = @()
  $mergedIndexes = @{}
  $managedKeys = @{}
  $inRoot = $true
  $inMergedTable = $false
  $skipSection = $false

  foreach ($line in $ManagedLines) {
    if ($line -match '^\s*([A-Za-z0-9_-]+)\s*=') {
      $managedKeys[$Matches[1]] = $true
    }
  }

  foreach ($line in $Lines) {
    if ($line -match '^\s*\[') {
      $inRoot = $false
      $skipSection = $false
      $header = ($line -replace '\s+#.*$', '').Trim()
      $tableName = $header.Trim('[', ']')
      $inMergedTable = $tableName -eq $Table

      if ($RemoveTables -contains $tableName) {
        $skipSection = $true
        continue
      }

      if ($inMergedTable) {
        continue
      }

      $result += $line
      continue
    }

    if ($skipSection) {
      continue
    }

    $key = if ($line -match '^\s*([A-Za-z0-9_-]+)\s*=') { $Matches[1] } else { "" }
    if ($inRoot -and $RootKeys -contains $key) {
      continue
    }

    if ($inMergedTable) {
      if ($managedKeys.ContainsKey($key)) {
        continue
      }
      if ($key) {
        if ($mergedIndexes.ContainsKey($key)) {
          $mergedLines[$mergedIndexes[$key]] = $line
        } else {
          $mergedIndexes[$key] = $mergedLines.Count
          $mergedLines += $line
        }
      } else {
        $mergedLines += $line
      }
      continue
    }

    $result += $line
  }

  return $result + "" + "[$Table]" + $mergedLines + $ManagedLines
}
