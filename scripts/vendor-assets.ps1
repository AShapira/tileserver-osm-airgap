param(
  [switch]$SkipFonts
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-TextFile($Url, $Path) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing
}

function Read-Json($Path) {
  Get-Content -Raw -Path $Path | ConvertFrom-Json
}

function Write-Json($Object, $Path) {
  $json = $Object | ConvertTo-Json -Depth 100
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
}

function Set-LocalStyle($InputPath, $OutputPath, $Name, $SpriteId) {
  $style = Read-Json $InputPath
  $style.name = $Name
  $style.metadata = [ordered]@{
    description = "$Name localized for air-gapped TileServer GL."
  }
  $style.glyphs = "/fonts/{fontstack}/{range}.pbf"

  $sources = [ordered]@{}
  $sources.openmaptiles = [ordered]@{
    type = "vector"
    url = "mbtiles://osm-vector.mbtiles"
  }
  $style.sources = $sources

  $layers = @()
  foreach ($layer in $style.layers) {
    if ($layer.PSObject.Properties.Name -contains "source") {
      if ($layer.source -ne "openmaptiles") {
        continue
      }
    }
    $layers += $layer
  }
  $style.layers = $layers

  if ($style.PSObject.Properties.Name -contains "sprite") {
    $style.sprite = "$SpriteId/sprite"
  }
  Write-Json $style $OutputPath
}

function Copy-StyleAsOpenMapTiles($InputPath, $OutputPath) {
  $style = Read-Json $InputPath
  $style.name = "OSM OpenMapTiles"
  $metadata = [ordered]@{
    description = "Carto-inspired OpenMapTiles-compatible vector style localized for air-gapped TileServer GL."
  }
  $style.metadata = $metadata
  $style.glyphs = "/fonts/{fontstack}/{range}.pbf"
  $style.sprite = "osm-bright/sprite"
  Write-Json $style $OutputPath
}

$upstream = Join-Path $repoRoot "dist/upstream"
$styles = Join-Path $repoRoot "tileserver/styles"
$sprites = Join-Path $repoRoot "tileserver/sprites"
$vendor = Join-Path $repoRoot "viewer/vendor"

New-Item -ItemType Directory -Force -Path $upstream,$styles,$sprites,$vendor | Out-Null

Get-TextFile "https://unpkg.com/maplibre-gl@5.5.0/dist/maplibre-gl.js" (Join-Path $vendor "maplibre-gl.js")
Get-TextFile "https://unpkg.com/maplibre-gl@5.5.0/dist/maplibre-gl.css" (Join-Path $vendor "maplibre-gl.css")

$styleSources = @(
  @{ Id = "osm-bright"; Name = "OSM Bright"; Url = "https://raw.githubusercontent.com/openmaptiles/osm-bright-gl-style/master/style.json"; Sprite = "https://openmaptiles.github.io/osm-bright-gl-style/sprite" },
  @{ Id = "dark-matter"; Name = "Dark Matter"; Url = "https://raw.githubusercontent.com/openmaptiles/dark-matter-gl-style/master/style.json"; Sprite = "https://openmaptiles.github.io/dark-matter-gl-style/sprite" },
  @{ Id = "osm-liberty"; Name = "OSM Liberty"; Url = "https://raw.githubusercontent.com/maputnik/osm-liberty/gh-pages/style.json"; Sprite = "https://maputnik.github.io/osm-liberty/sprites/osm-liberty" }
)

foreach ($source in $styleSources) {
  $rawPath = Join-Path $upstream "$($source.Id).json"
  Get-TextFile $source.Url $rawPath
  Set-LocalStyle $rawPath (Join-Path $styles "$($source.Id).json") $source.Name $source.Id

  $spriteDir = Join-Path $sprites $source.Id
  New-Item -ItemType Directory -Force -Path $spriteDir | Out-Null
  foreach ($suffix in @(".json", ".png", "@2x.json", "@2x.png")) {
    try {
      Get-TextFile "$($source.Sprite)$suffix" (Join-Path $spriteDir "sprite$suffix")
    } catch {
      Write-Warning "Could not download sprite$suffix for $($source.Id): $($_.Exception.Message)"
    }
  }
}

Copy-StyleAsOpenMapTiles (Join-Path $styles "osm-bright.json") (Join-Path $styles "osm-openmaptiles.json")

if (-not $SkipFonts) {
  $fontsPath = Join-Path $repoRoot "tileserver/fonts"
  if (Test-Path (Join-Path $fontsPath ".git")) {
    git -C $fontsPath pull --ff-only
  } else {
    $tmpFonts = Join-Path $repoRoot "dist/upstream/fonts"
    if (Test-Path $tmpFonts) {
      Remove-Item -Path $tmpFonts -Recurse -Force
    }
    git clone --depth 1 --branch gh-pages https://github.com/openmaptiles/fonts.git $tmpFonts
    Get-ChildItem -Path $fontsPath -Force | Where-Object { $_.Name -ne "README.md" } | Remove-Item -Recurse -Force
    Get-ChildItem -Path $tmpFonts -Force | Where-Object { $_.Name -ne ".git" } | Copy-Item -Destination $fontsPath -Recurse -Force
  }
}

Write-Host "Vendored MapLibre, styles, sprites, and fonts for local air-gapped serving."
