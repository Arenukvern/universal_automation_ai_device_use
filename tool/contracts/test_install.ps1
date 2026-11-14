# Contract tests for install.ps1 (Windows junction + upgrade while exe is open).
#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$InstallScript = Join-Path $Root "install.ps1"
if (-not (Test-Path $InstallScript)) { throw "missing install.ps1" }

function New-MockCliExe([string]$OutPath, [string]$VersionLabel, [switch]$FailVersion) {
  $src = Join-Path $env:TEMP "ua-mock-$([guid]::NewGuid().ToString()).cs"
  $failRet = if ($FailVersion) { "return 1;" } else { "return 0;" }
  @"
using System;
using System.Threading;
public static class UaMock {
  public static int Main(string[] args) {
    if (args.Length > 0 && args[0] == "--version") {
      Console.WriteLine("$VersionLabel");
      $failRet
    }
    if (args.Length > 0 && args[0] == "--help") { return 0; }
    if (args.Length > 0 && args[0] == "--hold") {
      Thread.Sleep(120000);
      return 0;
    }
    return 0;
  }
}
"@ | Set-Content -Path $src -Encoding UTF8
  $csc = Join-Path ${env:WINDIR} "Microsoft.NET\Framework64/v4.0.30319/csc.exe"
  if (-not (Test-Path $csc)) { $csc = "csc.exe" }
  & $csc /nologo /out:$OutPath $src
  if (-not (Test-Path $OutPath)) { throw "failed to compile mock CLI" }
}

function Publish-MockRelease([string]$Dir, [string]$Version, [string]$Label, [switch]$Broken) {
  $pkg = Join-Path $Dir "universal_automation_${Version}_windows-x64"
  if (Test-Path $pkg) { Remove-Item -Recurse -Force $pkg }
  New-Item -ItemType Directory -Path (Join-Path $pkg "bin") -Force | Out-Null
  $exe = Join-Path $pkg "bin\universal_automation.exe"
  New-MockCliExe -OutPath $exe -VersionLabel $Label -FailVersion:$Broken
  $zip = Join-Path $Dir "universal_automation_${Version}_windows-x64.zip"
  if (Test-Path $zip) { Remove-Item -Force $zip }
  Compress-Archive -Path $pkg -DestinationPath $zip -Force
  $hash = (Get-FileHash -Algorithm SHA256 -Path $zip).Hash.ToLower()
  Set-Content -Path (Join-Path $Dir "checksums.txt") -Value "$hash  $(Split-Path -Leaf $zip)" -Encoding ascii
}

$tmp = Join-Path $env:TEMP "ua-install-test-$PID"
$share = Join-Path $tmp "share"
$rel = Join-Path $tmp "release"
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $rel -Force | Out-Null

Publish-MockRelease -Dir $rel -Version "1.0.0" -Label "mock-1.0.0"

$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { throw "python required for local release fixture server" }
$server = Start-Process -FilePath $py.Source -ArgumentList "-m", "http.server", "8765", "--directory", $rel -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 2
$base = "http://127.0.0.1:8765"

try {
  $env:UNIVERSAL_AUTOMATION_SHARE = $share
  $installOutput = & $InstallScript -Version "1.0.0" -BaseUrl $base *>&1 | Out-String
  if ($installOutput -notmatch '\\current\\bin\\') { throw "MCP snippet must use \\current\\bin\\ path" }
  if ($installOutput -match '\\versions\\') { throw "MCP snippet must not expose \\versions\\ physical path" }
  $currentExe = Join-Path $share "current\bin\universal_automation.exe"
  if (-not (Test-Path $currentExe)) { throw "missing current exe after first install" }
  $v1 = & $currentExe --version
  if ($LASTEXITCODE -ne 0) { throw "v1 --version exit $LASTEXITCODE" }
  if ($v1 -ne "mock-1.0.0") { throw "expected mock-1.0.0 got $v1" }

  $holder = Start-Process -FilePath $currentExe -ArgumentList "--hold" -PassThru

  try {
    Publish-MockRelease -Dir $rel -Version "1.0.0" -Label "mock-1.0.0-bump"
    & $InstallScript -Version "1.0.0" -BaseUrl $base
    $v2 = & $currentExe --version
    if ($LASTEXITCODE -ne 0) { throw "v2 --version exit $LASTEXITCODE" }
    if ($v2 -ne "mock-1.0.0-bump") { throw "expected mock-1.0.0-bump got $v2" }
  } finally {
    if (-not $holder.HasExited) { Stop-Process -Id $holder.Id -Force -ErrorAction SilentlyContinue }
  }

  $beforeBroken = & $currentExe --version
  Publish-MockRelease -Dir $rel -Version "1.0.0" -Label "broken" -Broken
  try {
    & $InstallScript -Version "1.0.0" -BaseUrl $base
    throw "broken binary install must fail"
  } catch {
    if ($_.Exception.Message -notmatch "smoke") { throw $_ }
  }
  $afterBroken = & $currentExe --version
  if ($LASTEXITCODE -ne 0 -or $afterBroken -ne $beforeBroken) {
    throw "active install changed after failed broken install"
  }

  & $InstallScript -Rollback
  $rb = & $currentExe --version
  if ($LASTEXITCODE -ne 0) { throw "rollback --version failed" }
  if ($rb -ne "mock-1.0.0") { throw "rollback expected prior install mock-1.0.0 got $rb" }

  Write-Host "test_install.ps1: OK"
}
finally {
  if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}