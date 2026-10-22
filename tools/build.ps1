# Builds dist/ — a self-contained production bundle of Ludo Zing Mymensingh for YouTube Playables and
# static hosting (Cloudflare Pages). No third-party CDNs: three.js and the fonts ship inside the bundle; the only
# external script is YouTube's own Playables SDK, which the Playables docs require to load before game code.
# Usage:  powershell -ExecutionPolicy Bypass -File tools\build.ps1
$ErrorActionPreference = 'Stop'
$root   = Split-Path $PSScriptRoot -Parent
$vendor = Join-Path $root 'vendor'     # third-party files, downloaded once and reused
$dist   = Join-Path $root 'dist'
$zip    = Join-Path $root 'ludo-king-mymensingh-playables.zip'
New-Item -ItemType Directory -Force $vendor, (Join-Path $vendor 'fonts') | Out-Null

# 1. three.js r128 — the version the game is written against
$three = Join-Path $vendor 'three.min.js'
if (-not (Test-Path $three)) {
  curl.exe -sSfL -o $three 'https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js'
  if ($LASTEXITCODE -ne 0) { throw 'Could not download three.js' }
}

# 2. Fonts: latin subset of Lilita One, Nunito 500/700/800 and Orbitron 700 (studio splash), rewritten to local files.
#    The list is re-downloaded whenever this family list changes.
$fontQuery = 'family=Lilita+One&family=Nunito:wght@500;700;800&family=Orbitron:wght@700&display=swap'
$fontsCss  = Join-Path $vendor 'fonts.css'
$fontsKey  = Join-Path $vendor 'fonts.query'
if ((Test-Path $fontsCss) -and (-not (Test-Path $fontsKey) -or (Get-Content -Raw $fontsKey).Trim() -ne $fontQuery)) { Remove-Item $fontsCss }
if (-not (Test-Path $fontsCss)) {
  $ua  = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36'
  $css = (curl.exe -sSfL -A $ua "https://fonts.googleapis.com/css2?$fontQuery") -join "`n"
  if ($LASTEXITCODE -ne 0) { throw 'Could not download the font list' }
  $out = New-Object System.Text.StringBuilder
  foreach ($m in [regex]::Matches($css, '/\* latin \*/\s*(@font-face\s*\{[^}]*\})')) {
    $block = $m.Groups[1].Value
    $url   = [regex]::Match($block, 'url\((https://fonts\.gstatic\.com/[^)]+)\)').Groups[1].Value
    $family = ([regex]::Match($block, "font-family:\s*'([^']+)'").Groups[1].Value) -replace '[^A-Za-z0-9]', ''
    $file  = $family + '-' + ([IO.Path]::GetFileNameWithoutExtension(($url -split '/')[-1]) -replace '[^A-Za-z0-9_-]', '') + '.woff2'
    $dest  = Join-Path $vendor "fonts\$file"
    if (-not (Test-Path $dest)) { curl.exe -sSfL -o $dest $url; if ($LASTEXITCODE -ne 0) { throw "Could not download $url" } }
    [void]$out.AppendLine(($block -replace [regex]::Escape($url), "fonts/$file"))
  }
  if ($out.Length -eq 0) { throw 'No latin font faces found' }
  [IO.File]::WriteAllText($fontsCss, $out.ToString())
  [IO.File]::WriteAllText($fontsKey, $fontQuery)
}

# 3. index.html: full document, SDK first, local three.js + fonts, no test hook
$src = [IO.File]::ReadAllText((Join-Path $root 'index.html'))
$src = [regex]::Replace($src, '<link rel="preconnect"[^>]*>\r?\n', '')
$src = [regex]::Replace($src, '<link rel="stylesheet" href="https://fonts\.googleapis\.com[^>]*>\r?\n', '')
$src = $src.Replace('<script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>', '<script src="three.min.js"></script>')
$src = [regex]::Replace($src, '// Test hook for tests/pair-rules\.js[^\n]*\n[^\n]*window\.__ludo = [^\n]*\n', '')
if ($src -match 'window\.__ludo') { throw 'Test hook still present' }
$i = $src.IndexOf('<div id="stage">')
if ($i -lt 0) { throw 'Stage container not found in index.html' }
$head = @'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<script src="https://www.youtube.com/game_api/v1"></script>
<link rel="stylesheet" href="fonts.css">
<style>:root{padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}body{margin:0;font:14px system-ui,sans-serif}img{max-width:100%}</style>
'@
$html = $head + $src.Substring(0, $i) + "</head>`n<body>`n" + $src.Substring($i) + "`n</body>`n</html>`n"

if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
New-Item -ItemType Directory -Force (Join-Path $dist 'fonts') | Out-Null
[IO.File]::WriteAllText((Join-Path $dist 'index.html'), $html, (New-Object Text.UTF8Encoding $false))
Copy-Item $three, $fontsCss $dist
Copy-Item (Join-Path $vendor 'fonts\*.woff2') (Join-Path $dist 'fonts')

# 4. Checks against the Playables stability rules (sizes, names, relative paths, external requests)
$files = Get-ChildItem -Recurse -File $dist
$total = ($files | Measure-Object Length -Sum).Sum
$bad   = $files | Where-Object { $_.Name -notmatch '^[A-Za-z0-9_.-]+$' }
$big   = $files | Where-Object { $_.Length -ge 30MB }
$ext   = [regex]::Matches($html, '(?:src|href)="(https?://[^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -ne 'https://www.youtube.com/game_api/v1' }
if ($bad) { throw "File names not allowed: $($bad.Name -join ', ')" }
if ($big) { throw "Files over 30 MiB: $($big.Name -join ', ')" }
if ($total -ge 30MB) { throw 'Bundle over 30 MiB' }
if ($files.Count -gt 8000) { throw 'More than 8000 files' }
if ($ext) { throw "External requests in index.html: $($ext -join ', ')" }

if (Test-Path $zip) { Remove-Item -Force $zip }
# Zip with forward-slash entry names. (Windows PowerShell 5.1's Compress-Archive writes "fonts\x.woff2", which hosts
# such as Cloudflare Pages then serve as a file literally named with a backslash, so fonts/x.woff2 404s.)
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($zip, 'Create')
try {
  foreach ($f in $files) {
    $entry = $f.FullName.Substring($dist.Length + 1).Replace('\', '/')
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $f.FullName, $entry, 'Optimal')
  }
} finally { $archive.Dispose() }
$bad = [System.IO.Compression.ZipFile]::OpenRead($zip)
try { if ($bad.Entries | Where-Object { $_.FullName -match '\\' }) { throw 'Zip contains backslash paths' } } finally { $bad.Dispose() }
'Build OK'
$files | ForEach-Object { '{0,-46} {1,9:N0} bytes' -f $_.FullName.Substring($dist.Length + 1), $_.Length }
'Total: {0:N0} bytes in {1} files (limit 30 MiB initial, 8000 files). Zip: {2}' -f $total, $files.Count, $zip
