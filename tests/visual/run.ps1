# Visual + layout regression tests for the LOCKED home screen.
# No Node/Python needed: drives the installed Chrome (or Edge) headless over the DevTools protocol (like Playwright does),
# with exact viewport emulation and software WebGL (SwiftShader) so frames are reproducible; System.Drawing does the diff.
#
#   powershell -ExecutionPolicy Bypass -File tests\visual\run.ps1              # build, then test (exit code 1 on failure)
#   powershell -ExecutionPolicy Bypass -File tests\visual\run.ps1 -SkipBuild   # test the current dist/
#   ... run.ps1 -UpdateBaseline -Approval "Approved by <name> on <date>: <what changed>"
#        Only after the user has explicitly approved a visual change. Never run it just to make a failing test pass.
param(
  [switch]$SkipBuild,
  [switch]$UpdateBaseline,
  [string]$Approval = '',
  [int]$Port = 8790,               # static server for dist/
  [int]$DebugPort = 9333,          # Chrome DevTools port
  [double]$MaxDiffRatio = 0.005,   # share of pixels allowed to differ (anti-aliasing noise); a real layout change is far above this
  [int]$ChannelTolerance = 40      # per-channel difference that still counts as the same pixel
)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$here = $PSScriptRoot
$dist = Join-Path $root 'dist'
$baseDir = Join-Path $here 'baseline'
$outDir = Join-Path $here 'output'
$baseline = Join-Path $baseDir 'home-390x844.png'
New-Item -ItemType Directory -Force $baseDir, $outDir | Out-Null

if ($UpdateBaseline -and $Approval.Trim().Length -lt 10) {
  throw 'Refusing to update the baseline without -Approval "Approved by <name> on <date>: <change>". Baselines change only after an explicitly approved visual change.'
}
$chrome = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
            "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") |
          Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) { throw 'Chrome or Edge is required for the visual tests.' }

if (-not $SkipBuild) {
  $b = & powershell -ExecutionPolicy Bypass -File (Join-Path $root 'tools\build.ps1')
  if ($LASTEXITCODE -or -not ($b -match 'Build OK')) { $b; throw 'Build failed' }
  $b | Select-Object -Last 1
}
if (-not (Test-Path (Join-Path $dist 'index.html'))) { throw 'dist/ is missing; run without -SkipBuild' }
Copy-Item (Join-Path $here 'vt-checks.js') (Join-Path $dist 'vt-checks.js') -Force   # test-only file, never part of the zip

$server = Start-Process powershell -ArgumentList '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'tools\serve.ps1'), '-Port', $Port -WindowStyle Hidden -PassThru
$prof = Join-Path $env:TEMP ('ludo-vt-' + [guid]::NewGuid().ToString('N'))
$browser = Start-Process $chrome -WindowStyle Hidden -PassThru -ArgumentList @('--headless=new', "--remote-debugging-port=$DebugPort", "--user-data-dir=$prof",
  '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--no-first-run', '--no-default-browser-check', '--hide-scrollbars', '--mute-audio',
  '--force-color-profile=srgb', '--disable-background-timer-throttling', '--disable-renderer-backgrounding', 'about:blank')

$failures = New-Object System.Collections.Generic.List[string]
$ws = $null
try {
  # ---- minimal DevTools-protocol client ----
  $target = $null
  for ($k = 0; $k -lt 50 -and -not $target; $k++) {
    try { $target = (Invoke-RestMethod "http://127.0.0.1:$DebugPort/json/list") | Where-Object { $_.type -eq 'page' } | Select-Object -First 1 } catch { Start-Sleep -Milliseconds 200 }
  }
  if (-not $target) { throw 'Could not reach headless Chrome' }
  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  [void]$ws.ConnectAsync([Uri]$target.webSocketDebuggerUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
  $script:msgId = 0
  function Send-Cdp([string]$method, $params = @{}) {
    $script:msgId++
    $json = @{ id = $script:msgId; method = $method; params = $params } | ConvertTo-Json -Depth 10 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    [void]$ws.SendAsync([ArraySegment[byte]]::new($bytes), 'Text', $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
    $buf = New-Object byte[] 1048576
    while ($true) {
      $ms = New-Object IO.MemoryStream
      do { $r = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), [Threading.CancellationToken]::None).GetAwaiter().GetResult(); $ms.Write($buf, 0, $r.Count) } while (-not $r.EndOfMessage)
      $text = [Text.Encoding]::UTF8.GetString($ms.ToArray())
      if ($text -match ('^\{"id":' + $script:msgId + '[,}]')) {
        $obj = $text | ConvertFrom-Json
        if ($obj.error) { throw "CDP $method failed: $($obj.error.message)" }
        return $obj.result
      }
    }
  }
  function Get-Js([string]$expr) { (Send-Cdp 'Runtime.evaluate' @{ expression = $expr; returnByValue = $true }).result.value }
  function Open-Home([int]$w, [int]$h) {
    Send-Cdp 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = $h; deviceScaleFactor = 1; mobile = $false } | Out-Null
    Send-Cdp 'Page.navigate' @{ url = "http://localhost:$Port/index.html?vt=1&run=$([guid]::NewGuid().ToString('N'))" } | Out-Null
    $deadline = (Get-Date).AddSeconds(60)
    do { Start-Sleep -Milliseconds 300; $t = [string](Get-Js 'document.title') } until ($t.StartsWith('VT:') -or (Get-Date) -gt $deadline)
    return $t
  }
  Send-Cdp 'Page.enable' | Out-Null
  Send-Cdp 'Emulation.setScrollbarsHidden' @{ hidden = $true } | Out-Null

  # ---- 1. layout checks at the reference size and other sizes (LOCK numbers apply at 390x844 only) ----
  foreach ($size in @(@(390, 844), @(320, 568), @(430, 932), @(844, 390), @(768, 1024), @(1366, 768))) {
    $label = "$($size[0])x$($size[1])"
    $title = Open-Home $size[0] $size[1]
    $json = Get-Js "(document.getElementById('vt-report')||{}).textContent||''"
    if (-not $json) { $msg = "[$label] layout report missing (title: $title)"; "Layout $label : FAIL"; "  $msg"; $failures.Add($msg); continue }
    $r = $json | ConvertFrom-Json
    "Layout {0,-9}: {1}" -f $label, $(if ($r.pass) { "PASS ($($r.total) checks)" } else { "FAIL ($($r.failed) of $($r.total))" })
    foreach ($c in $r.checks | Where-Object { -not $_.ok }) { $msg = "[$label] $($c.name) -> $($c.detail | ConvertTo-Json -Compress)"; "  $msg"; $failures.Add($msg) }
    if ($label -eq '390x844') {
      if ($r.metrics.stage[0] -ne 390 -or $r.metrics.stage[1] -ne 844) { $failures.Add("[390x844] reference viewport not applied (stage $($r.metrics.stage -join 'x'))") }
      '  metrics: ' + ($r.metrics | ConvertTo-Json -Compress)
    }
  }

  # ---- 2. screenshot of the frozen home screen at 390x844 ----
  $null = Open-Home 390 844
  Start-Sleep -Milliseconds 500
  $png = (Send-Cdp 'Page.captureScreenshot' @{ format = 'png' }).data
  $shot = Join-Path $outDir 'home-390x844.png'
  [IO.File]::WriteAllBytes($shot, [Convert]::FromBase64String($png))

  if ($UpdateBaseline) {
    if ($failures.Count) { throw 'Layout checks fail; fix them before approving a new baseline.' }
    Copy-Item $shot $baseline -Force
    Add-Content (Join-Path $baseDir 'APPROVALS.md') ("- {0:yyyy-MM-dd HH:mm} - {1}" -f (Get-Date), $Approval.Trim()) -Encoding UTF8
    "Baseline updated: $baseline"
  } elseif (-not (Test-Path $baseline)) {
    $failures.Add('No approved baseline yet (tests/visual/baseline/home-390x844.png).')
  } else {
    # pixel diff in compiled C# (a PowerShell loop over 330,000 pixels takes minutes)
    if (-not ('LudoVt.Diff' -as [type])) {
      Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
namespace LudoVt {
  public static class Diff {
    // returns { differingPixels, minX, minY, maxX, maxY } and writes a diff image (red = different, grey = same)
    public static int[] Compare(string basePath, string shotPath, string diffPath, int tol) {
      using (var a = new Bitmap(basePath)) using (var b = new Bitmap(shotPath)) {
        if (a.Width != b.Width || a.Height != b.Height) return new[] { -1, a.Width, a.Height, b.Width, b.Height };
        var rect = new Rectangle(0, 0, a.Width, a.Height); var fmt = PixelFormat.Format32bppArgb;
        var da = a.LockBits(rect, ImageLockMode.ReadOnly, fmt); var db = b.LockBits(rect, ImageLockMode.ReadOnly, fmt);
        int n = da.Stride * a.Height; var pa = new byte[n]; var pb = new byte[n]; var pd = new byte[n];
        Marshal.Copy(da.Scan0, pa, 0, n); Marshal.Copy(db.Scan0, pb, 0, n); a.UnlockBits(da); b.UnlockBits(db);
        int bad = 0, minX = a.Width, minY = a.Height, maxX = -1, maxY = -1;
        for (int y = 0; y < a.Height; y++) for (int x = 0; x < a.Width; x++) {
          int i = y * da.Stride + x * 4;
          int d = Math.Max(Math.Abs(pa[i] - pb[i]), Math.Max(Math.Abs(pa[i + 1] - pb[i + 1]), Math.Abs(pa[i + 2] - pb[i + 2])));
          if (d > tol) { bad++; pd[i] = 0; pd[i + 1] = 0; pd[i + 2] = 255; if (x < minX) minX = x; if (x > maxX) maxX = x; if (y < minY) minY = y; if (y > maxY) maxY = y; }
          else { byte g = (byte)((pa[i] + pa[i + 1] + pa[i + 2]) / 9 + 170); pd[i] = g; pd[i + 1] = g; pd[i + 2] = g; }
          pd[i + 3] = 255;
        }
        using (var dimg = new Bitmap(a.Width, a.Height, fmt)) {
          var dd = dimg.LockBits(rect, ImageLockMode.WriteOnly, fmt); Marshal.Copy(pd, 0, dd.Scan0, n); dimg.UnlockBits(dd); dimg.Save(diffPath);
        }
        return new[] { bad, minX, minY, maxX, maxY, a.Width * a.Height };
      }
    }
  }
}
"@
    }
    $diffPath = Join-Path $outDir 'home-390x844.diff.png'
    $res = [LudoVt.Diff]::Compare($baseline, $shot, $diffPath, $ChannelTolerance)
    if ($res[0] -lt 0) { $failures.Add("Screenshot size $($res[3])x$($res[4]) differs from baseline $($res[1])x$($res[2])") }
    else {
      $ratio = $res[0] / $res[5]
      "Screenshot 390x844: {0:P3} of pixels differ from the approved baseline (limit {1:P1})" -f $ratio, $MaxDiffRatio
      if ($ratio -gt $MaxDiffRatio) { $failures.Add(("Screenshot differs from the approved baseline: {0:P2} of pixels, region x {1}-{2}, y {3}-{4}. See {5}" -f $ratio, $res[1], $res[3], $res[2], $res[4], $diffPath)) }
    }
  }
} finally {
  if ($ws) { try { $ws.Dispose() } catch {} }
  Stop-Process -Id $browser.Id -Force -ErrorAction SilentlyContinue
  Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($prof) } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 300
  Remove-Item -Recurse -Force $prof -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $dist 'vt-checks.js') -ErrorAction SilentlyContinue
}

if ($failures.Count) { ''; 'VISUAL REGRESSION: FAIL'; $failures | ForEach-Object { " - $_" }; exit 1 }
''; 'VISUAL REGRESSION: PASS'
