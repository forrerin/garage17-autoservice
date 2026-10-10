# Локальный сервер для собранного сайта: ничего устанавливать не нужно, работает на любом Windows 10/11
param([switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot '..\garage17-autoservice' | Resolve-Path
$base = '/garage17-autoservice/'

$types = @{
  '.html' = 'text/html; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'; '.css' = 'text/css; charset=utf-8'
  '.svg' = 'image/svg+xml'; '.png' = 'image/png'; '.jpg' = 'image/jpeg'; '.webp' = 'image/webp'; '.woff2' = 'font/woff2'; '.woff' = 'font/woff'
  '.json' = 'application/json; charset=utf-8'; '.webmanifest' = 'application/manifest+json'; '.txt' = 'text/plain; charset=utf-8'
}

# первый свободный порт начиная с 8080
$listener = $null
foreach ($port in 8080..8099) {
  try {
    $l = New-Object System.Net.HttpListener
    $l.Prefixes.Add("http://localhost:$port/")
    $l.Start()
    $listener = $l
    break
  } catch { }
}
if (-not $listener) { Write-Host 'Не нашёлся свободный порт 8080–8099. Закройте лишние программы и запустите снова.'; exit 1 }

$url = "http://localhost:$port$base"
Write-Host ''
Write-Host '  Демо запущено: Автосервис «Гараж 17»' -ForegroundColor Green
Write-Host "  Клиентское приложение:  $url"
Write-Host "  Приложение мастера:     ${url}master/"
Write-Host "  Панель управления:      ${url}admin/"
Write-Host ''
Write-Host '  Сайт открылся в браузере. Пока это окно открыто — сайт работает.'
Write-Host '  Чтобы выключить, просто закройте окно.'
Write-Host ''
if (-not $NoBrowser) { Start-Process $url }

function Send($res, $file, $method, $status) {
  $bytes = [IO.File]::ReadAllBytes($file)
  $ext = [IO.Path]::GetExtension($file).ToLower()
  $res.StatusCode = $status
  $res.ContentType = if ($types.ContainsKey($ext)) { $types[$ext] } else { 'application/octet-stream' }
  $res.ContentLength64 = $bytes.Length
  if ($method -eq 'GET') { $res.OutputStream.Write($bytes, 0, $bytes.Length) }
}

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $req = $ctx.Request
  $res = $ctx.Response
  try {
    $path = [Uri]::UnescapeDataString($req.Url.AbsolutePath)
    if (-not $path.StartsWith($base)) {
      $res.StatusCode = 302
      $res.RedirectLocation = $base
    } elseif ($req.HttpMethod -ne 'GET' -and $req.HttpMethod -ne 'HEAD') {
      $res.StatusCode = 405
    } else {
      $rel = $path.Substring($base.Length)
      $file = [IO.Path]::GetFullPath((Join-Path $root $rel))
      if ($file.StartsWith($root.Path) -and (Test-Path $file -PathType Container) -and -not $rel.EndsWith('/') -and $rel -ne '') {
        # как на GitHub Pages: папка без слэша — редирект на папку со слэшем
        $res.StatusCode = 301
        $res.RedirectLocation = "$path/"
      } else {
        if ($rel -eq '' -or $rel.EndsWith('/')) { $file = Join-Path $file 'index.html' }
        if ($file.StartsWith($root.Path) -and (Test-Path $file -PathType Leaf)) {
          Send $res $file $req.HttpMethod 200
        } else {
          # адреса внутри приложения (/book, /master/week…) открывает 404.html — как на GitHub Pages
          Send $res (Join-Path $root '404.html') $req.HttpMethod 404
        }
      }
    }
  } catch {
    $res.StatusCode = 500
  } finally {
    $res.Close()
  }
}
