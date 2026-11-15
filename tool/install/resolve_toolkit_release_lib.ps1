# Shared logic for install.ps1 — skip toolkit releases without full binary assets.

function Get-RequiredBinaryAssetNames([string]$Version) {
  @(
    "universal_automation_${Version}_darwin-arm64.tar.gz"
    "universal_automation_${Version}_darwin-x64.tar.gz"
    "universal_automation_${Version}_linux-x64.tar.gz"
    "universal_automation_${Version}_windows-x64.zip"
    "checksums.txt"
  )
}

function Test-ToolkitReleaseAssetSetComplete([string]$Version, [string[]]$AssetNames) {
  $required = Get-RequiredBinaryAssetNames $Version
  $have = [System.Collections.Generic.HashSet[string]]::new([string[]]$AssetNames)
  foreach ($name in $required) {
    if (-not $have.Contains($name)) { return $false }
  }
  return $true
}

function Resolve-LatestToolkitVersionFromReleases([object[]]$Releases) {
  foreach ($rel in $Releases) {
    if ($rel.draft -eq $true) { continue }
    $tag = [string]$rel.tag_name
    if ($tag -notmatch '^universal_automation_toolkit-v(.+)$') { continue }
    $ver = $Matches[1]
    $names = @($rel.assets | ForEach-Object { $_.name })
    if (Test-ToolkitReleaseAssetSetComplete $ver $names) {
      return $ver
    }
  }
  return $null
}