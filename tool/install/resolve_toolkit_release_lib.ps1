# Resolve latest toolkit release by tag names + HTTP HEAD probes (no releases JSON).

function Get-RequiredBinaryAssetNames([string]$Version) {
  @(
    "universal_automation_${Version}_darwin-arm64.tar.gz"
    "universal_automation_${Version}_darwin-x64.tar.gz"
    "universal_automation_${Version}_linux-x64.tar.gz"
    "universal_automation_${Version}_windows-x64.zip"
    "checksums.txt"
  )
}

function Test-PrereleaseVersion([string]$Version) {
  return $Version -match '-'
}

function Parse-MatchingRefsToolkitTags([string]$Json) {
  $tags = [System.Collections.Generic.List[string]]::new()
  foreach ($m in [regex]::Matches($Json, '"ref"\s*:\s*"refs/tags/(universal_automation_toolkit-v[^"]+)"')) {
    $tags.Add($m.Groups[1].Value)
  }
  return $tags
}

function Get-ToolkitReleaseTags([string]$Repo) {
  if ($env:UNIVERSAL_AUTOMATION_TOOLKIT_TAGS_FIXTURE) {
    return Get-Content -LiteralPath $env:UNIVERSAL_AUTOMATION_TOOLKIT_TAGS_FIXTURE |
      Where-Object { $_ -and $_ -notmatch '^\s*#' }
  }
  if ($env:UNIVERSAL_AUTOMATION_MATCHING_REFS_URL) {
    $uri = $env:UNIVERSAL_AUTOMATION_MATCHING_REFS_URL
    try {
      $json = (Invoke-WebRequest -Uri $uri -UseBasicParsing).Content
    } catch {
      throw [System.InvalidOperationException]::new("UA_RESOLVE_NETWORK: $($_.Exception.Message)")
    }
    return Parse-MatchingRefsToolkitTags $json
  }
  $git = Get-Command git -ErrorAction SilentlyContinue
  if ($git) {
    $remote = "https://github.com/$Repo.git"
    $lines = & git ls-remote --tags $remote 'refs/tags/universal_automation_toolkit-v*' 2>$null
    $tags = @()
    foreach ($line in $lines) {
      if ($line -match '\trefs/tags/(universal_automation_toolkit-v.+)$') {
        $tagName = $Matches[1]
        if ($tagName -notmatch '\^\{\}$') { $tags += $tagName }
      }
    }
    if ($tags.Count -gt 0) { return $tags }
  }
  $uri = "https://api.github.com/repos/$Repo/git/matching-refs/tags/universal_automation_toolkit-v"
  try {
    $json = (Invoke-WebRequest -Uri $uri -UseBasicParsing).Content
  } catch {
    throw [System.InvalidOperationException]::new("UA_RESOLVE_NETWORK: $($_.Exception.Message)")
  }
  return Parse-MatchingRefsToolkitTags $json
}

function Sort-ToolkitTagsByVersionDesc([string[]]$Tags) {
  $rows = foreach ($tag in $Tags) {
    if ($tag -notmatch '^universal_automation_toolkit-v(.+)$') { continue }
    $ver = $Matches[1]
    if (Test-PrereleaseVersion $ver) { continue }
  if ($ver -match '^(\d+)\.(\d+)\.(\d+)$') {
      $key = [int]$Matches[1] * 100000000 + [int]$Matches[2] * 10000 + [int]$Matches[3]
      [pscustomobject]@{ Key = $key; Tag = $tag; Ver = $ver }
    }
  }
  $rows | Sort-Object -Property Key -Descending | ForEach-Object { $_.Tag }
}

function Get-ReleaseDownloadUrl([string]$Repo, [string]$Tag, [string]$Asset) {
  if ($env:UNIVERSAL_AUTOMATION_PROBE_BASE_URL) {
    $base = $env:UNIVERSAL_AUTOMATION_PROBE_BASE_URL.TrimEnd('/')
    return "$base/$Tag/$Asset"
  }
  return "https://github.com/$Repo/releases/download/$Tag/$Asset"
}

function Test-HttpHeadOk([string]$Url, [string]$Tag, [string]$Asset) {
  if ($env:UNIVERSAL_AUTOMATION_ASSET_PROBE_MAP -and (Test-Path -LiteralPath $env:UNIVERSAL_AUTOMATION_ASSET_PROBE_MAP)) {
    $lines = Get-Content -LiteralPath $env:UNIVERSAL_AUTOMATION_ASSET_PROBE_MAP
    foreach ($line in $lines) {
      if (-not $line -or $line.StartsWith('#')) { continue }
      $parts = $line -split "`t", 3
      if ($parts.Count -ge 3 -and $parts[0] -eq $Tag -and $parts[1] -eq $Asset) {
        $code = $parts[2].Trim()
        return ($code -match '^[23]')
      }
    }
    return $false
  }
  try {
    $req = [System.Net.WebRequest]::Create($Url)
    $req.Method = 'HEAD'
    $req.Timeout = 15000
    $resp = $req.GetResponse()
    $code = [int][System.Net.HttpStatusCode]$resp.StatusCode
    $resp.Close()
    return ($code -ge 200 -and $code -lt 400)
  } catch {
    return $false
  }
}

function Test-TagHasCompleteBinarySet([string]$Repo, [string]$Tag, [string]$Version) {
  foreach ($asset in (Get-RequiredBinaryAssetNames $Version)) {
    $url = Get-ReleaseDownloadUrl $Repo $Tag $asset
    if (-not (Test-HttpHeadOk $url $Tag $asset)) { return $false }
  }
  return $true
}

function Resolve-LatestToolkitVersion([string]$Repo) {
  $tags = Get-ToolkitReleaseTags $Repo
  foreach ($tag in (Sort-ToolkitTagsByVersionDesc $tags)) {
    $ver = $tag -replace '^universal_automation_toolkit-v', ''
    if (Test-TagHasCompleteBinarySet $Repo $tag $ver) {
      return $ver
    }
  }
  return $null
}