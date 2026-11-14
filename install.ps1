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
$VersionsDir = Join-Path $ShareRoot "versions"
$PreviousFile = Join-Path $ShareRoot "previous"
$BinDir = if ($env:UNIVERSAL_AUTOMATION_BIN_DIR) { $env:UNIVERSAL_AUTOMATION_BIN_DIR } else { Join-Path $env:LOCALAPPDATA "Programs\universal-automation\bin" }
$BinLink = Join-Path $BinDir "universal-automation.exe"
$PointerFile = Join-Path $ShareRoot "current-install.txt"

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

function Resolve-CliInTree([string]$Root) {
  $a = Join-Path $Root "bin\universal_automation.exe"
  if (Test-Path $a) { return $a }
  $b = Join-Path $Root "bin\universal-automation.exe"
  if (Test-Path $b) { return $b }
  return $null
}

function Switch-BinShim([string]$Exe) {
  New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
  $tmp = "$BinLink.$PID.new"
  Copy-Item -Force $Exe $tmp
  if (Test-Path $BinLink) { Remove-Item -Force $BinLink }
  Move-Item -Force $tmp $BinLink
}

function Record-PreviousInstall {
  if (-not (Test-Path $PointerFile)) { return }
  $current = Get-Content -Raw $PointerFile
  if ($current) { Set-Content -Path $PreviousFile -Value $current.Trim() -NoNewline }
}

function Prune-VersionDirs([string]$Ver, [string]$KeepCurrent, [string]$KeepPrevious) {
  if (-not (Test-Path $VersionsDir)) { return }
  Get-ChildItem -Path $VersionsDir -Directory | ForEach-Object {
    $name = $_.Name
    if ($name -notlike "$Ver-*") { return }
    if ($_.FullName -eq $KeepCurrent) { return }
    if ($KeepPrevious -and $_.FullName -eq $KeepPrevious) { return }
    Remove-Item -Recurse -Force $_.FullName
  }
}

if ($Rollback) {
  if (-not (Test-Path $PreviousFile)) { throw "No previous install recorded at $PreviousFile" }
  $prevRoot = (Get-Content -Raw $PreviousFile).Trim()
  if (-not (Test-Path $prevRoot)) { throw "Previous install dir missing: $prevRoot" }
  $cli = Resolve-CliInTree $prevRoot
  if (-not $cli) { throw "CLI missing under $prevRoot" }
  if (Test-Path $PointerFile) {
    $current = (Get-Content -Raw $PointerFile).Trim()
    if ($current) { Set-Content -Path $PreviousFile -Value $current -NoNewline }
  }
  Switch-BinShim $cli
  Set-Content -Path $PointerFile -Value $prevRoot -NoNewline
  Write-Host "Rolled back to $(Split-Path -Leaf $prevRoot)"
  exit 0
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

  $matched = Select-String -Path $checksumsPath -Pattern "^[0-9a-fA-F]+\s+$([regex]::Escape($archive))$" | Select-Object -First 1
  if (-not $matched) { throw "Missing checksum for $archive" }
  $expected = ($matched.Line -split '\s+', 2)[0]
  $hash = (Get-FileHash -Algorithm SHA256 -Path $archivePath).Hash.ToLower()
  if ($hash -ne $expected.ToLower()) {
    throw "Checksum mismatch for $archive"
  }

  Expand-Archive -Path $archivePath -DestinationPath $temp -Force
  $packageDir = Join-Path $temp "universal_automation_${Version}_windows-x64"
  if (-not (Test-Path $packageDir)) {
    $packageDir = Get-ChildItem -Path $temp -Directory | Select-Object -First 1 -ExpandProperty FullName
  }

  New-Item -ItemType Directory -Path $VersionsDir -Force | Out-Null
  $staging = Join-Path $VersionsDir "$Version.staging.$PID"
  $installRoot = Join-Path $VersionsDir "$Version-$(Get-Date -Format 'yyyyMMddHHmmss')-$PID"
  if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
  Copy-Item -Recurse -Force $packageDir $staging
  Move-Item -Force $staging $installRoot

  $exe = Resolve-CliInTree $installRoot
  if (-not $exe) {
    Remove-Item -Recurse -Force $installRoot
    throw "CLI exe missing in staged bundle"
  }

  try {
    & $exe --version | Out-Null
  } catch {
    Remove-Item -Recurse -Force $installRoot
    throw "Staged binary failed --version smoke test; not switching active install"
  }

  Record-PreviousInstall
  Switch-BinShim $exe
  Set-Content -Path $PointerFile -Value $installRoot -NoNewline

  $keepPrevious = $null
  if (Test-Path $PreviousFile) {
    $keepPrevious = (Get-Content -Raw $PreviousFile).Trim()
  }
  Prune-VersionDirs -Ver $Version -KeepCurrent $installRoot -KeepPrevious $keepPrevious

  & $BinLink --help | Out-Null
  $ver = & $BinLink --version
  Write-Host "Installed universal-automation $ver"
  Write-Host "Install root: $installRoot"
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