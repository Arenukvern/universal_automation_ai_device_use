#Requires -Version 5.1
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Lib = Join-Path $Root "tool\install\resolve_toolkit_release_lib.ps1"
if (-not (Test-Path -LiteralPath $Lib)) { throw "missing $Lib" }
. $Lib

$tags = New-TemporaryFile
$probe = New-TemporaryFile
@"
universal_automation_toolkit-v0.6.2
"@ | Set-Content -LiteralPath $tags
@"
universal_automation_toolkit-v0.6.2	universal_automation_0.6.2_darwin-arm64.tar.gz	200
universal_automation_toolkit-v0.6.2	universal_automation_0.6.2_darwin-x64.tar.gz	200
universal_automation_toolkit-v0.6.2	universal_automation_0.6.2_linux-x64.tar.gz	200
universal_automation_toolkit-v0.6.2	universal_automation_0.6.2_windows-x64.zip	200
universal_automation_toolkit-v0.6.2	checksums.txt	200
"@ | Set-Content -LiteralPath $probe

$env:UNIVERSAL_AUTOMATION_TOOLKIT_TAGS_FIXTURE = $tags.FullName
$env:UNIVERSAL_AUTOMATION_ASSET_PROBE_MAP = $probe.FullName
$env:UNIVERSAL_AUTOMATION_PROBE_BASE_URL = "http://probe.invalid"

$ver = Resolve-LatestToolkitVersion "test/repo"
if ($ver -ne "0.6.2") { throw "expected 0.6.2 got $ver" }

$install = Join-Path $Root "install.ps1"
$head = Get-Content -LiteralPath $install -TotalCount 30
if (-not ($head -match '\.\s+\$__UaLib')) {
  throw "install.ps1 must dot-source resolve_toolkit_release_lib.ps1 at script scope"
}

Write-Host "test_resolve_toolkit_release.ps1: OK"