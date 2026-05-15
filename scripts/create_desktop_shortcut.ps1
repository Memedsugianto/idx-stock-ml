# Buat shortcut di Desktop Windows -> start_app.bat
$ErrorActionPreference = "Stop"

$scriptsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$batPath = Join-Path $scriptsDir "start_app.bat"
$batPath = (Resolve-Path $batPath).Path

$desktop = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktop "IDX Stock ML.lnk"

$wsh = New-Object -ComObject WScript.Shell
$sc = $wsh.CreateShortcut($shortcutPath)
$sc.TargetPath = $batPath
$sc.WorkingDirectory = $scriptsDir
$sc.Description = "Jalankan IDX Stock ML (API + Flutter Chrome)"
$sc.WindowStyle = 1
# Ikon shell (bisa diganti path .ico jika ada)
$sc.IconLocation = "$env:SystemRoot\System32\imageres.dll,109"
$sc.Save()

Write-Host "Shortcut dibuat:"
Write-Host "  $shortcutPath"
Write-Host ""
Write-Host "Double-click 'IDX Stock ML' di Desktop untuk menjalankan aplikasi."
