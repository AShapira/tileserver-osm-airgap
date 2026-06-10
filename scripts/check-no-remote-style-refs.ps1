$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$targets = @(
  (Join-Path $repoRoot "tileserver/styles"),
  (Join-Path $repoRoot "viewer")
)

$files = $targets | ForEach-Object {
  Get-ChildItem -Path $_ -File -Recurse -ErrorAction SilentlyContinue
}

$matches = $files |
  Where-Object { $_.FullName -notmatch '\\vendor\\|/vendor/' } |
  Select-String -Pattern 'https?://(?!localhost(:[0-9]+)?[/"'']|127\.0\.0\.1(:[0-9]+)?[/"''])' -ErrorAction SilentlyContinue

if ($matches) {
  $matches | ForEach-Object { Write-Host "$($_.Path):$($_.LineNumber): $($_.Line.Trim())" }
  throw "Remote references found in local style/viewer files."
}

$fontPath = Join-Path $repoRoot "tileserver/fonts"
$missingFonts = @()
foreach ($styleFile in Get-ChildItem -Path (Join-Path $repoRoot "tileserver/styles") -Filter "*.json" -File) {
  $style = Get-Content -Raw -Path $styleFile.FullName | ConvertFrom-Json
  if ($style.glyphs -ne "{fontstack}/{range}.pbf") {
    throw "Style $($styleFile.Name) must use the relative glyph URL {fontstack}/{range}.pbf."
  }

  foreach ($layer in $style.layers) {
    if ($null -eq $layer.layout -or -not ($layer.layout.PSObject.Properties.Name -contains "text-font")) {
      continue
    }
    foreach ($font in $layer.layout."text-font") {
      if (-not (Test-Path (Join-Path $fontPath "$font/0-255.pbf"))) {
        $missingFonts += "$($styleFile.Name): $font"
      }
    }
  }
}

if ($missingFonts) {
  $missingFonts | Sort-Object -Unique | ForEach-Object { Write-Host $_ }
  throw "Bundled styles reference missing font glyphs."
}

Write-Host "No remote references or missing style fonts found."
