# Sync Android SDK platform-tools into windows/platform-tools for bundling.
param(
  [string]$SdkPlatformTools = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$dst = Join-Path $root "windows\platform-tools"

if (-not $SdkPlatformTools) {
  foreach ($envName in @("ANDROID_HOME", "ANDROID_SDK_ROOT")) {
    $val = [Environment]::GetEnvironmentVariable($envName)
    if ($val) {
      $candidate = Join-Path $val "platform-tools"
      if (Test-Path (Join-Path $candidate "adb.exe")) {
        $SdkPlatformTools = $candidate
        break
      }
    }
  }
}

if (-not $SdkPlatformTools) {
  $default = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools"
  if (Test-Path (Join-Path $default "adb.exe")) {
    $SdkPlatformTools = $default
  }
}

if (-not $SdkPlatformTools -or -not (Test-Path (Join-Path $SdkPlatformTools "adb.exe"))) {
  throw "找不到 platform-tools。请安装 Android SDK 或传入 -SdkPlatformTools 路径。"
}

New-Item -ItemType Directory -Force -Path $dst | Out-Null
$files = @(
  "adb.exe",
  "AdbWinApi.dll",
  "AdbWinUsbApi.dll",
  "sqlite3.exe",
  "libwinpthread-1.dll",
  "NOTICE.txt",
  "source.properties"
)

foreach ($f in $files) {
  $from = Join-Path $SdkPlatformTools $f
  if (Test-Path $from) {
    Copy-Item -Force $from (Join-Path $dst $f)
    Write-Host "OK  $f"
  } else {
    Write-Host "SKIP $f (not found)"
  }
}

Write-Host "Synced -> $dst"
