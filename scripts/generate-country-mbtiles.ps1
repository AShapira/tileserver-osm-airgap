[CmdletBinding()]
param(
  [string[]]$Countries,
  [string[]]$Pbf,
  [string]$SnapshotDate,
  [string]$Output = "data/mbtiles/osm-vector.mbtiles",
  [string]$Memory = $env:PLANETILER_JAVA_OPTS,
  [switch]$Offline,
  [switch]$Refresh,
  [switch]$DownloadOnly,
  [switch]$MergeOnly,
  [switch]$Force,
  [switch]$PlanOnly
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$dataRoot = Join-Path $repoRoot "data"
$countryDir = Join-Path $dataRoot "input/countries"
$combinedDir = Join-Path $dataRoot "input/combined"
$sourceDir = Join-Path $dataRoot "sources"
$indexPath = Join-Path $sourceDir "geofabrik-index-v1.json"
$indexUrl = "https://download.geofabrik.de/index-v1.json"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if (-not $Memory) { $Memory = "-Xmx8g" }

function Expand-ListValues {
  param([string[]]$Values)
  $result = @()
  foreach ($value in @($Values)) {
    if ($null -eq $value) { continue }
    foreach ($item in ($value -split ',')) {
      $trimmed = $item.Trim()
      if ($trimmed) { $result += $trimmed }
    }
  }
  return @($result)
}

function Get-ContainedPath {
  param(
    [string]$Path,
    [string]$Description
  )
  if ([System.IO.Path]::IsPathRooted($Path)) {
    $fullPath = [System.IO.Path]::GetFullPath($Path)
  } else {
    $fullPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
  }
  $rootWithSeparator = [System.IO.Path]::GetFullPath($dataRoot).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
  if (-not $fullPath.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "$Description must be under data/ so containers can access it: $Path"
  }
  return $fullPath
}

function Get-DataRelativePath {
  param([string]$FullPath)
  $rootWithSeparator = [System.IO.Path]::GetFullPath($dataRoot).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
  $normalizedPath = [System.IO.Path]::GetFullPath($FullPath)
  if (-not $normalizedPath.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Path is outside data/: $FullPath"
  }
  return $normalizedPath.Substring($rootWithSeparator.Length).Replace('\', '/')
}

function Get-GeofabrikIndex {
  if ($Offline) {
    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
      throw "Offline country resolution requires the cached index at data/sources/geofabrik-index-v1.json."
    }
    return Get-Content -LiteralPath $indexPath -Raw | ConvertFrom-Json
  }

  if ((Test-Path -LiteralPath $indexPath -PathType Leaf) -and -not $Refresh) {
    return Get-Content -LiteralPath $indexPath -Raw | ConvertFrom-Json
  }

  Write-Host "Reading Geofabrik region index..."
  $response = Invoke-WebRequest -Uri $indexUrl -UseBasicParsing
  $index = $response.Content | ConvertFrom-Json
  if (-not $PlanOnly) {
    New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null
    [System.IO.File]::WriteAllText($indexPath, $response.Content, $utf8NoBom)
  }
  return $index
}

function Resolve-GeofabrikRegion {
  param(
    [object]$Index,
    [string]$Country
  )
  $query = $Country.Trim().ToLowerInvariant()
  if ($query -eq "israel") { $query = "israel-and-palestine" }

  $matches = @($Index.features | Where-Object {
    $id = [string]$_.properties.id
    $name = [string]$_.properties.name
    $iso = @($_.properties.'iso3166-1:alpha2')
    $id.ToLowerInvariant() -eq $query -or
      $name.ToLowerInvariant() -eq $query -or
      (@($iso | Where-Object { ([string]$_).ToLowerInvariant() -eq $query }).Count -gt 0)
  })

  if ($matches.Count -eq 0) {
    throw "Unknown Geofabrik country or region '$Country'. Use a Geofabrik region ID, exact display name, or ISO alpha-2 code."
  }
  if ($matches.Count -gt 1) {
    $ids = ($matches | ForEach-Object { $_.properties.id }) -join ", "
    throw "Country or region '$Country' is ambiguous: $ids"
  }
  if (-not $matches[0].properties.urls.pbf) {
    throw "Geofabrik region '$($matches[0].properties.id)' does not publish a PBF URL."
  }
  return $matches[0]
}

function Get-CurlCommand {
  $command = Get-Command curl -CommandType Application -ErrorAction SilentlyContinue
  if (-not $command) {
    $command = Get-Command curl.exe -CommandType Application -ErrorAction SilentlyContinue
  }
  if (-not $command) {
    throw "curl is required for resumable country downloads."
  }
  return $command.Source
}

function Invoke-Download {
  param(
    [string]$Url,
    [string]$Destination,
    [switch]$Resume
  )
  $curl = Get-CurlCommand
  $partial = "$Destination.part"
  $arguments = @("--fail", "--location", "--retry", "3", "--output", $partial)
  if ($Resume) { $arguments += @("--continue-at", "-") }
  $arguments += $Url
  & $curl @arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Download failed: $Url"
  }
  Move-Item -LiteralPath $partial -Destination $Destination -Force
}

function Get-ExpectedMd5 {
  param([string]$ChecksumPath)
  $content = Get-Content -LiteralPath $ChecksumPath -Raw
  if ($content -notmatch '(?i)\b([0-9a-f]{32})\b') {
    throw "Invalid Geofabrik MD5 file: $ChecksumPath"
  }
  return $Matches[1].ToLowerInvariant()
}

function Test-PbfChecksum {
  param(
    [string]$PbfPath,
    [string]$ChecksumPath
  )
  $expected = Get-ExpectedMd5 -ChecksumPath $ChecksumPath
  $actual = (Get-FileHash -LiteralPath $PbfPath -Algorithm MD5).Hash.ToLowerInvariant()
  if ($actual -ne $expected) {
    throw "Checksum mismatch for $PbfPath. Expected $expected but calculated $actual."
  }
  return $actual
}

$Countries = @(Expand-ListValues -Values $Countries)
$Pbf = @(Expand-ListValues -Values $Pbf)

if (($Countries.Count -eq 0) -eq ($Pbf.Count -eq 0)) {
  throw "Specify exactly one input mode: -Countries or -Pbf."
}
if ($Countries.Count -gt 0 -and -not $SnapshotDate) {
  throw "-SnapshotDate is required with -Countries so every extract comes from one common snapshot."
}
if ($Pbf.Count -gt 0 -and $SnapshotDate) {
  throw "-SnapshotDate applies only to -Countries, not local -Pbf inputs."
}
if ($DownloadOnly -and $MergeOnly) {
  throw "-DownloadOnly and -MergeOnly cannot be used together."
}
if ($DownloadOnly -and $Pbf.Count -gt 0) {
  throw "-DownloadOnly is only valid with -Countries."
}
if ($Refresh -and $Offline) {
  throw "-Refresh cannot be used with -Offline."
}

$outputPath = Get-ContainedPath -Path $Output -Description "Output"
if (-not $PlanOnly -and -not $DownloadOnly -and -not $MergeOnly -and (Test-Path -LiteralPath $outputPath -PathType Leaf) -and -not $Force) {
  throw "Output MBTiles already exists: $(Get-DataRelativePath $outputPath). Use -Force to replace it."
}
$records = @()
$inputPaths = @()
$canonicalIds = @()
$snapshotStamp = $null

if ($Countries.Count -gt 0) {
  try {
    $snapshot = [datetime]::ParseExact($SnapshotDate, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None)
  } catch {
    throw "-SnapshotDate must use YYYY-MM-DD, for example 2026-06-01."
  }
  $snapshotStamp = $snapshot.ToString("yyMMdd")
  $index = Get-GeofabrikIndex
  $seenIds = @{}

  foreach ($country in $Countries) {
    $feature = Resolve-GeofabrikRegion -Index $index -Country $country
    $id = [string]$feature.properties.id
    if ($seenIds.ContainsKey($id)) { continue }
    $seenIds[$id] = $true
    $canonicalIds += $id

    $latestUrl = [string]$feature.properties.urls.pbf
    if ($latestUrl -notmatch '-latest\.osm\.pbf$') {
      throw "Unexpected Geofabrik PBF URL for '$id': $latestUrl"
    }
    $pbfUrl = $latestUrl -replace '-latest\.osm\.pbf$', "-$snapshotStamp.osm.pbf"
    $checksumUrl = "$pbfUrl.md5"
    $pbfPath = Join-Path $countryDir "$id-$snapshotStamp.osm.pbf"
    $checksumPath = "$pbfPath.md5"

    $records += [pscustomobject][ordered]@{
      requested = $country
      regionId = $id
      name = [string]$feature.properties.name
      sourceUrl = $pbfUrl
      checksumUrl = $checksumUrl
      pbfPath = Get-DataRelativePath -FullPath $pbfPath
      md5 = $null
    }
    $inputPaths += $pbfPath
  }
} else {
  foreach ($path in $Pbf) {
    $fullPath = Get-ContainedPath -Path $path -Description "PBF input"
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
      throw "PBF input does not exist: $path"
    }
    if ([System.IO.Path]::GetExtension($fullPath) -ne ".pbf") {
      throw "PBF input must end in .pbf: $path"
    }
    $inputPaths += $fullPath
    $canonicalIds += [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetFileNameWithoutExtension($fullPath))
    $records += [pscustomobject][ordered]@{
      requested = $path
      regionId = $null
      name = [System.IO.Path]::GetFileName($fullPath)
      sourceUrl = $null
      checksumUrl = $null
      pbfPath = Get-DataRelativePath -FullPath $fullPath
      md5 = (Get-FileHash -LiteralPath $fullPath -Algorithm MD5).Hash.ToLowerInvariant()
    }
  }
}

$nameParts = @($canonicalIds | Sort-Object -Unique | ForEach-Object { ($_ -replace '[^a-zA-Z0-9._-]', '-').ToLowerInvariant() })
$combinedBase = $nameParts -join "_"
if ($snapshotStamp) { $combinedBase = "$combinedBase-$snapshotStamp" }
$mergedPath = Join-Path $combinedDir "$combinedBase.osm.pbf"
$manifestPath = Join-Path $combinedDir "$combinedBase.manifest.json"

Write-Host "Input mode: $(if ($Countries.Count -gt 0) { 'Geofabrik countries' } else { 'local PBF files' })"
if ($snapshotStamp) { Write-Host "Snapshot: $SnapshotDate" }
Write-Host "Inputs:"
foreach ($record in $records) {
  Write-Host "  $($record.name): $($record.pbfPath)"
  if ($record.sourceUrl) { Write-Host "    $($record.sourceUrl)" }
}
Write-Host "Merged PBF: $(Get-DataRelativePath -FullPath $mergedPath)"
Write-Host "Output MBTiles: $(Get-DataRelativePath -FullPath $outputPath)"
Write-Host "Planetiler memory: $Memory"

if ($PlanOnly) {
  Write-Host "Plan only: no PBF files, merged output, manifest, or MBTiles were changed."
  exit 0
}

New-Item -ItemType Directory -Force -Path $countryDir, $combinedDir, (Split-Path -Parent $outputPath) | Out-Null

if ($Countries.Count -gt 0) {
  for ($i = 0; $i -lt $records.Count; $i++) {
    $pbfPath = $inputPaths[$i]
    $checksumPath = "$pbfPath.md5"
    if ($Refresh) {
      Remove-Item -LiteralPath $pbfPath, $checksumPath, "$pbfPath.part", "$checksumPath.part" -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path -LiteralPath $checksumPath -PathType Leaf)) {
      if ($Offline) { throw "Offline checksum file is missing: $(Get-DataRelativePath $checksumPath)" }
      Write-Host "Downloading checksum for $($records[$i].regionId)..."
      Invoke-Download -Url $records[$i].checksumUrl -Destination $checksumPath
    }
    if (-not (Test-Path -LiteralPath $pbfPath -PathType Leaf)) {
      if ($Offline) { throw "Offline PBF is missing: $(Get-DataRelativePath $pbfPath)" }
      Write-Host "Downloading $($records[$i].regionId)..."
      Invoke-Download -Url $records[$i].sourceUrl -Destination $pbfPath -Resume
    }
    try {
      $records[$i].md5 = Test-PbfChecksum -PbfPath $pbfPath -ChecksumPath $checksumPath
    } catch {
      if ($Offline) { throw }
      Write-Warning $_.Exception.Message
      Write-Host "Removing the invalid cached PBF; rerun the command to download it again."
      Remove-Item -LiteralPath $pbfPath -Force -ErrorAction SilentlyContinue
      throw
    }
    Write-Host "Verified $($records[$i].regionId): $($records[$i].md5)"
  }
}

function Write-ProvenanceManifest {
  param([string]$Stage)
  $manifest = [ordered]@{
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    stage = $Stage
    inputMode = $(if ($Countries.Count -gt 0) { "geofabrik" } else { "local" })
    snapshotDate = $(if ($snapshotStamp) { $SnapshotDate } else { $null })
    regions = $records
    mergedPbf = Get-DataRelativePath -FullPath $mergedPath
    outputMbtiles = Get-DataRelativePath -FullPath $outputPath
    planetilerJavaOpts = $Memory
  }
  [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 8), $utf8NoBom)
}

if ($DownloadOnly) {
  Write-ProvenanceManifest -Stage "downloaded"
  Write-Host "Download complete. Provenance: $(Get-DataRelativePath $manifestPath)"
  exit 0
}

$mergeRequired = -not (Test-Path -LiteralPath $mergedPath -PathType Leaf) -or $Force -or $Refresh
if ($MergeOnly -and -not $mergeRequired) {
  throw "Merged PBF already exists: $(Get-DataRelativePath $mergedPath). Use -Force to replace it."
}
if ($mergeRequired) {
  $mergeArgs = @("merge")
  foreach ($path in $inputPaths) { $mergeArgs += "/data/$(Get-DataRelativePath $path)" }
  $mergeArgs += @("--output", "/data/$(Get-DataRelativePath $mergedPath)", "--progress")
  if ((Test-Path -LiteralPath $mergedPath) -or $Force -or $Refresh) { $mergeArgs += "--overwrite" }

  Write-Host "Merging $($inputPaths.Count) PBF files with Osmium..."
  Push-Location $repoRoot
  try {
    docker compose --profile generate run --rm osmium @mergeArgs
    if ($LASTEXITCODE -ne 0) { throw "Osmium merge failed with exit code $LASTEXITCODE." }
  } finally {
    Pop-Location
  }
} else {
  Write-Host "Reusing existing merged PBF: $(Get-DataRelativePath $mergedPath)"
}

Write-ProvenanceManifest -Stage "merged"
if ($MergeOnly) {
  Write-Host "Merge complete. Provenance: $(Get-DataRelativePath $manifestPath)"
  exit 0
}

$mergedRelative = "data/$(Get-DataRelativePath $mergedPath)"
$outputRelative = "data/$(Get-DataRelativePath $outputPath)"
Write-Host "Generating MBTiles with Planetiler..."
& "$PSScriptRoot/generate-vector-mbtiles.ps1" -Pbf $mergedRelative -Output $outputRelative -Memory $Memory -Offline:$Offline
if ($LASTEXITCODE -ne 0) { throw "Planetiler generation failed with exit code $LASTEXITCODE." }

Write-ProvenanceManifest -Stage "generated"
Write-Host "MBTiles generation complete: $(Get-DataRelativePath $outputPath)"
Write-Host "Provenance: $(Get-DataRelativePath $manifestPath)"
