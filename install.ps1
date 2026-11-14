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
$CurrentLink = Join-Path $ShareRoot "current"
$ProgramsBin = if ($env:UNIVERSAL_AUTOMATION_BIN_DIR) { $env:UNIVERSAL_AUTOMATION_BIN_DIR } else { Join-Path $env:LOCALAPPDATA "Programs\universal-automation\bin" }

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

function Resolve-PhysicalRoot([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  try {
    $resolved = [System.IO.Directory]::ResolveLinkTarget($Path, $true)
    if ($null -ne $resolved) {
      return $resolved.FullName
    }
  } catch {
    # PowerShell 5.1 fallback below.
  }
  $item = Get-Item -LiteralPath $Path -Force
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    $target = $item.Target
    if ($target -is [System.Array]) {
      $target = $target[0]
    }
    if ($target) { return $target }
  }
  return $item.FullName
}

function Resolve-CliInTree([string]$Root) {
  $physical = Resolve-PhysicalRoot $Root
  if (-not $physical) { return $null }
  $a = Join-Path $physical "bin\universal_automation.exe"
  if (Test-Path -LiteralPath $a) { return $a }
  $b = Join-Path $physical "bin\universal-automation.exe"
  if (Test-Path -LiteralPath $b) { return $b }
  return $null
}

function Get-JunctionTarget([string]$Path) {
  return Resolve-PhysicalRoot $Path
}

function Invoke-CliSmoke([string]$Exe) {
  & $Exe --version | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "CLI smoke failed (--version exit $LASTEXITCODE): $Exe"
  }
}

function Remove-DirectoryJunction([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return }
  cmd /c "rmdir `"$Path`"" | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "failed to remove junction: $Path"
  }
}

function Switch-CurrentJunction([string]$InstallRoot) {
  $abs = (Resolve-Path -LiteralPath $InstallRoot).ProviderPath
  $parent = $ShareRoot
  $tmpPath = Join-Path $parent ".current-$PID"
  Remove-DirectoryJunction $tmpPath
  Remove-DirectoryJunction $CurrentLink
  $out = cmd /c "mklink /J `"$tmpPath`" `"$abs`""
  if ($LASTEXITCODE -ne 0) {
    throw "mklink /J failed ($LASTEXITCODE): $out"
  }
  Rename-Item -LiteralPath $tmpPath -NewName "current"
}

function Record-PreviousInstall {
  $target = Get-JunctionTarget $CurrentLink
  if (-not $target) { return }
  if ($target -is [System.Array]) {
    $target = $target[0]
  }
  if ($target) {
    Set-Content -Path $PreviousFile -Value $target.Trim() -NoNewline
  }
}

function Normalize-PathKey([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
  return [System.IO.Path]::GetFullPath($Path).TrimEnd('\').ToLowerInvariant()
}

function Prune-VersionDirs([string]$Ver, [string]$KeepCurrent, [string]$KeepPrevious) {
  if (-not (Test-Path $VersionsDir)) { return }
  $keepCurrentKey = Normalize-PathKey $KeepCurrent
  $keepPreviousKey = Normalize-PathKey $KeepPrevious
  Get-ChildItem -Path $VersionsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $name = $_.Name
    if ($name -notlike "$Ver-*" -and $name -notlike "$Ver.staging.*") { return }
    $fullKey = Normalize-PathKey $_.FullName
    if ($fullKey -eq $keepCurrentKey) { return }
    if ($keepPreviousKey -and $fullKey -eq $keepPreviousKey) { return }
    try {
      Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
    } catch {
      Write-Warning "Skipped pruning in-use directory: $($_.FullName)"
    }
  }
}

if ($Rollback) {
  if (-not (Test-Path $PreviousFile)) { throw "No previous install recorded at $PreviousFile" }
  $prevRoot = (Get-Content -Raw $PreviousFile).Trim()
  if (-not (Test-Path $prevRoot)) { throw "Previous install dir missing: $prevRoot" }
  $cli = Resolve-CliInTree $prevRoot
  if (-not $cli) { throw "CLI missing under $prevRoot" }
  $currentTarget = Get-JunctionTarget $CurrentLink
  if ($currentTarget -is [System.Array]) { $currentTarget = $currentTarget[0] }
  if ($currentTarget) {
    Set-Content -Path $PreviousFile -Value $currentTarget.Trim() -NoNewline
  }
  Switch-CurrentJunction $prevRoot
  Invoke-CliSmoke (Resolve-CliInTree $CurrentLink)
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
  $unique = [guid]::NewGuid().ToString("N").Substring(0, 12)
  $staging = Join-Path $VersionsDir "$Version.staging.$PID.$unique"
  $installRoot = Join-Path $VersionsDir "$Version-$(Get-Date -Format 'yyyyMMddHHmmss')-$PID-$unique"
  if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
  Copy-Item -Recurse -Force $packageDir $staging
  Move-Item -Force $staging $installRoot

  $exe = Resolve-CliInTree $installRoot
  if (-not $exe) {
    Remove-Item -Recurse -Force $installRoot
    throw "CLI exe missing in staged bundle"
  }

  try {
    Invoke-CliSmoke $exe
  } catch {
    Remove-Item -Recurse -Force $installRoot
    throw "Staged binary failed --version smoke test; not switching active install"
  }

  Record-PreviousInstall
  Switch-CurrentJunction $installRoot

  $activeExe = Resolve-CliInTree $CurrentLink
  if (-not $activeExe) {
    $phys = Resolve-PhysicalRoot $CurrentLink
    throw "Active CLI missing under $CurrentLink (resolved: $phys)"
  }

  $keepPrevious = $null
  if (Test-Path $PreviousFile) {
    $keepPrevious = (Get-Content -Raw $PreviousFile).Trim()
  }
  Prune-VersionDirs -Ver $Version -KeepCurrent $installRoot -KeepPrevious $keepPrevious
  & $activeExe --help | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Active CLI --help failed" }
  $ver = & $activeExe --version
  if ($LASTEXITCODE -ne 0) { throw "Active CLI --version failed" }

  $physCurrent = Resolve-PhysicalRoot $CurrentLink
  $cliForSnippet = Join-Path $physCurrent "bin\universal_automation.exe"
  if (-not (Test-Path -LiteralPath $cliForSnippet)) {
    $cliForSnippet = Join-Path $physCurrent "bin\universal-automation.exe"
  }

  Write-Host "Installed universal-automation $ver"
  Write-Host "Install root: $installRoot"
  Write-Host "Current junction: $CurrentLink"
  Write-Host "Add to PATH (optional): $ProgramsBin"
  Write-Host @"

MCP client snippet:
{
  "mcpServers": {
    "universal-automation": {
      "command": "$cliForSnippet",
      "args": ["serve", "--os"]
    }
  }
}
"@
}
finally {
  Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue
}