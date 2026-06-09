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

Write-Host "No remote style or viewer references found."
