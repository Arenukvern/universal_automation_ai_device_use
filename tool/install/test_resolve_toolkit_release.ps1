#Requires -Version 5.1
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Install = Join-Path $Root "install.ps1"
if (-not (Test-Path -LiteralPath $Install)) { throw "missing $Install" }

function New-MockCliExe([string]$OutPath, [string]$VersionLabel) {
  $src = Join-Path $env:TEMP "ua-mock-$([guid]::NewGuid().ToString()).cs"
  @"
using System;
public static class UaMock {
  public static int Main(string[] args) {
    if (args.Length > 0 && args[0] == "--version") {
      Console.WriteLine("$VersionLabel");
      return 0;
    }
    return 0;
  }
}
"@ | Set-Content -Path $src -Encoding UTF8
  $csc = Join-Path ${env:WINDIR} "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
  if (-not (Test-Path $csc)) { $csc = "csc.exe" }
  & $csc /nologo /out:$OutPath $src
  if (-not (Test-Path $OutPath)) { throw "failed to compile mock CLI" }
}

$ver = "0.6.2"
$tag = "universal_automation_toolkit-v$ver"
$archive = "universal_automation_${ver}_windows-x64.zip"
$fixtureRoot = Join-Path $env:TEMP "ua-resolve-e2e-$PID"
$tagDir = Join-Path $fixtureRoot $tag
if (Test-Path $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
$pkg = Join-Path $tagDir "universal_automation_${ver}_windows-x64"
New-Item -ItemType Directory -Path (Join-Path $pkg "bin") -Force | Out-Null
$stubExe = Join-Path $pkg "bin\universal_automation.exe"
New-MockCliExe -OutPath $stubExe -VersionLabel $ver
$zipPath = Join-Path $tagDir $archive
if (Test-Path $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path $pkg -DestinationPath $zipPath -Force
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash.ToLower()
Set-Content -Path (Join-Path $tagDir "checksums.txt") -Value "$hash  $archive" -Encoding ascii

$tags = New-TemporaryFile
$probe = New-TemporaryFile
$share = Join-Path $env:TEMP "ua-install-share-$PID"
@"
$tag
"@ | Set-Content -LiteralPath $tags
@"
$tag	$archive	200
$tag	checksums.txt	200
$tag	universal_automation_${ver}_darwin-arm64.tar.gz	200
$tag	universal_automation_${ver}_darwin-x64.tar.gz	200
$tag	universal_automation_${ver}_linux-x64.tar.gz	200
$tag	universal_automation_${ver}_windows-x64.zip	200
"@ | Set-Content -LiteralPath $probe

$port = 8765
$py = $null
try {
  $py = Start-Process -FilePath "python" -ArgumentList @(
    "-m", "http.server", $port.ToString(), "--bind", "127.0.0.1", "--directory", $fixtureRoot
  ) -PassThru -WindowStyle Hidden
  Start-Sleep -Seconds 1

  $env:UNIVERSAL_AUTOMATION_TOOLKIT_TAGS_FIXTURE = $tags.FullName
  $env:UNIVERSAL_AUTOMATION_ASSET_PROBE_MAP = $probe.FullName
  $env:UNIVERSAL_AUTOMATION_PROBE_BASE_URL = "http://probe.invalid"
  $env:UNIVERSAL_AUTOMATION_SHARE = $share
  $baseUrl = "http://127.0.0.1:$port/$tag"

  & $Install -Repo "test/repo" -BaseUrl $baseUrl
  if ($LASTEXITCODE -ne 0) { throw "install.ps1 no-version path failed with exit $LASTEXITCODE" }

  Remove-Item env:UNIVERSAL_AUTOMATION_TOOLKIT_TAGS_FIXTURE -ErrorAction SilentlyContinue
  $env:UNIVERSAL_AUTOMATION_MATCHING_REFS_URL = "http://127.0.0.1:9/unreachable"
  $netLines = & $Install -Repo "test/repo" *>&1
  $netExit = $LASTEXITCODE
  $net = (($netLines | ForEach-Object { "$_" }) -join "`n")
  if ($net -notmatch 'Network or TLS') {
    throw "expected network/TLS message from install.ps1 (got: $net)"
  }
  if ($netExit -ne 2) {
    throw "expected exit 2 for network error (got $netExit)"
  }
} finally {
  if ($py) { Stop-Process -Id $py.Id -Force -ErrorAction SilentlyContinue }
  Remove-Item env:UNIVERSAL_AUTOMATION_TOOLKIT_TAGS_FIXTURE -ErrorAction SilentlyContinue
  Remove-Item env:UNIVERSAL_AUTOMATION_ASSET_PROBE_MAP -ErrorAction SilentlyContinue
  Remove-Item env:UNIVERSAL_AUTOMATION_PROBE_BASE_URL -ErrorAction SilentlyContinue
  Remove-Item env:UNIVERSAL_AUTOMATION_SHARE -ErrorAction SilentlyContinue
  Remove-Item env:UNIVERSAL_AUTOMATION_MATCHING_REFS_URL -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath $share) { Remove-Item -LiteralPath $share -Recurse -Force -ErrorAction SilentlyContinue }
  if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "test_resolve_toolkit_release.ps1: OK"