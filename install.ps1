# Install universal-automation from GitHub release assets (Windows x64).
#Requires -Version 5.1
param(
  [string]$Version = $env:UNIVERSAL_AUTOMATION_VERSION,
  [string]$Repo = $(if ($env:UNIVERSAL_AUTOMATION_REPO) { $env:UNIVERSAL_AUTOMATION_REPO } else { "Arenukvern/universal_automation_ai_device_use" }),
  [string]$BaseUrl = $env:UNIVERSAL_AUTOMATION_BASE_URL,
  [switch]$Rollback
)

$ErrorActionPreference = "Stop"

$ShareRoot = if ($env:UNIVERSAL_AUTOMATION_SHARE) { $env:UNIVERSAL_AUTOMATION_SHARE } else { Join-Path $env:LOCALAPPDATA "universal-automation" }
$BinDir = if ($env:UNIVERSAL_AUTOMATION_BIN_DIR) { $env:UNIVERSAL_AUTOMATION_BIN_DIR } else { Join-Path $env:LOCALAPPDATA "Programs\universal-automation\bin" }
$BinLink = Join-Path $BinDir "universal-automation.exe"

function Resolve-LatestVersion {
  $uri = "https://api.github.com/repos/$Repo/releases?per_page=30"
  $releases = Invoke-RestMethod -Uri $uri -UseBasicParsing
  foreach ($r in $releases) {
    if ($r.tag_name -match '^universal_automation_toolkit-v(.+)$') {
      return $Matches[1]
    }
  }
  return $null
}

if ($Rollback) {
  Write-Error "Rollback: manually repoint $BinLink to a prior folder under $ShareRoot"
  exit 1
}

if (-not $Version) {
  $Version = Resolve-LatestVersion
}
if (-not $Version) {
  Write-Host "Specify -Version or build from source (plugin/install.sh on WSL or Dart SDK)." -ForegroundColor Red
  exit 1
}

$tag = "universal_automation_toolkit-v$Version"
$archive = "universal_automation_${Version}_windows-x64.zip"
if (-not $BaseUrl) {
  $BaseUrl = "https://github.com/$Repo/releases/download/$tag"
}

$temp = Join-Path $env:TEMP "ua-install-$([guid]::NewGuid().ToString())"
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try {
  $archivePath = Join-Path $temp $archive
  $checksumsPath = Join-Path $temp "checksums.txt"
  Invoke-WebRequest -Uri "$BaseUrl/$archive" -OutFile $archivePath -UseBasicParsing
  Invoke-WebRequest -Uri "$BaseUrl/checksums.txt" -OutFile $checksumsPath -UseBasicParsing

  $line = Select-String -Path $checksumsPath -Pattern " $archive`$" | Select-Object -First 1
  if (-not $line) { throw "Missing checksum for $archive" }
  $expected = ($line.Line -split '\s+')[0]
  $hash = (Get-FileHash -Algorithm SHA256 -Path $archivePath).Hash.ToLower()
  if ($hash -ne $expected.ToLower()) {
    throw "Checksum mismatch for $archive"
  }

  Expand-Archive -Path $archivePath -DestinationPath $temp -Force
  $packageDir = Join-Path $temp "universal_automation_${Version}_windows-x64"
  if (-not (Test-Path $packageDir)) {
    $packageDir = Get-ChildItem -Path $temp -Directory | Select-Object -First 1 -ExpandProperty FullName
  }

  $installRoot = Join-Path $ShareRoot $Version
  $staging = Join-Path (Split-Path $installRoot -Parent) ".staging-$Version-$PID"
  if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
  Copy-Item -Recurse -Force $packageDir $staging
  if (Test-Path $installRoot) { Remove-Item -Recurse -Force $installRoot }
  Move-Item $staging $installRoot

  New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
  $exe = Join-Path $installRoot "bin\universal_automation.exe"
  if (-not (Test-Path $exe)) { $exe = Join-Path $installRoot "bin\universal-automation.exe" }
  if (-not (Test-Path $exe)) { throw "CLI exe missing" }
  Copy-Item -Force $exe $BinLink

  & $BinLink --help | Out-Null
  $ver = & $BinLink --version
  Write-Host "Installed universal-automation $ver"
  Write-Host "Add to PATH: $BinDir"
  Write-Host @"

MCP client snippet:
{
  "mcpServers": {
    "universal-automation": {
      "command": "$BinLink",
      "args": ["serve", "--os"]
    }
  }
}
"@
}
finally {
  Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue
}