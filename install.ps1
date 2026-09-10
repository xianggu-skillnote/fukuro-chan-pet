$ErrorActionPreference = 'Stop'

$repoDir = $PSScriptRoot
$hookDir = Join-Path $HOME '.claude\hooks\fukuro-chan'
$imageDir = Join-Path $HOME 'fukuro-chan'
$settingsPath = Join-Path $HOME '.claude\settings.json'
$desktopDir = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktopDir 'fukuro-chan.lnk'

$imagePaths = @{
    idle    = Join-Path $imageDir 'idle.png'
    running = Join-Path $imageDir 'running.png'
    waiting = Join-Path $imageDir 'waiting.png'
}

Write-Host "fukuro-chan installer"
Write-Host "------------------------"

$missing = $imagePaths.GetEnumerator() | Where-Object { -not (Test-Path $_.Value) }
if ($missing) {
    Write-Host ""
    Write-Host "画像がまだ用意されていません。次のパスに、背景透過PNGを置いてから、もう一度このスクリプトを実行してください:" -ForegroundColor Yellow
    foreach ($m in $missing) {
        Write-Host "  $($m.Value)"
    }
    Write-Host ""
    Write-Host "($imageDir フォルダ自体が無い場合は作成してください)"
    exit 1
}

New-Item -ItemType Directory -Force -Path $hookDir | Out-Null
Copy-Item -Path (Join-Path $repoDir 'write-state.sh') -Destination (Join-Path $hookDir 'write-state.sh') -Force
Copy-Item -Path (Join-Path $repoDir 'pet.ps1') -Destination (Join-Path $hookDir 'pet.ps1') -Force
Write-Host "スクリプトを配置しました: $hookDir"

Add-Type -AssemblyName System.Drawing
$idlePng = $imagePaths.idle
$icoPath = Join-Path $hookDir 'pet.ico'
$bytes = [System.IO.File]::ReadAllBytes($idlePng)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$bmp = New-Object System.Drawing.Bitmap($ms)
$size = 64
$square = New-Object System.Drawing.Bitmap($size, $size)
$g = [System.Drawing.Graphics]::FromImage($square)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$scale = [Math]::Min($size / $bmp.Width, $size / $bmp.Height)
$w = [int]($bmp.Width * $scale)
$h = [int]($bmp.Height * $scale)
$x = [int](($size - $w) / 2)
$y = [int](($size - $h) / 2)
$g.DrawImage($bmp, $x, $y, $w, $h)
$g.Dispose()
$hIcon = $square.GetHicon()
$icon = [System.Drawing.Icon]::FromHandle($hIcon)
$fs = New-Object System.IO.FileStream($icoPath, [System.IO.FileMode]::Create)
$icon.Save($fs)
$fs.Close()
Write-Host "アイコンを生成しました: $icoPath"

$WshShell = New-Object -ComObject WScript.Shell
$shortcut = $WshShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = 'powershell.exe'
$petScriptPath = (Join-Path $hookDir 'pet.ps1')
$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$petScriptPath`""
$shortcut.IconLocation = $icoPath
$shortcut.WindowStyle = 1
$shortcut.Description = 'fukuro-chan desktop pet'
$shortcut.Save()
Write-Host "デスクトップショートカットを作成しました: $shortcutPath"

if (Test-Path $settingsPath) {
    $json = Get-Content -Raw -Path $settingsPath | ConvertFrom-Json
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path $settingsPath) | Out-Null
    $json = [PSCustomObject]@{}
}

if (-not ($json.PSObject.Properties.Name -contains 'hooks')) {
    $json | Add-Member -NotePropertyName 'hooks' -NotePropertyValue ([PSCustomObject]@{})
}

$hookScriptPath = (Join-Path $hookDir 'write-state.sh') -replace '\\', '/'

$eventsToArgs = [ordered]@{
    'SessionStart'     = 'idle'
    'SessionEnd'       = 'idle'
    'UserPromptSubmit' = 'running'
    'PreToolUse'       = 'running'
    'PostToolUse'      = 'running'
    'Notification'     = 'notification'
    'Stop'             = 'idle'
}

foreach ($eventName in $eventsToArgs.Keys) {
    $arg = $eventsToArgs[$eventName]
    $command = "bash `"$hookScriptPath`" $arg"

    $newEntry = [PSCustomObject]@{
        matcher = ''
        hooks   = @(
            [PSCustomObject]@{
                type    = 'command'
                command = $command
            }
        )
    }

    $hasEvent = $json.hooks.PSObject.Properties.Name -contains $eventName
    if (-not $hasEvent) {
        $json.hooks | Add-Member -NotePropertyName $eventName -NotePropertyValue @($newEntry)
    } else {
        $existingEntries = @($json.hooks.$eventName)
        $alreadyInstalled = $false
        foreach ($entry in $existingEntries) {
            foreach ($h in @($entry.hooks)) {
                if ($h.command -like '*fukuro-chan/write-state.sh*') {
                    $alreadyInstalled = $true
                }
            }
        }
        if (-not $alreadyInstalled) {
            $json.hooks.$eventName = $existingEntries + @($newEntry)
        }
    }
}

$jsonText = $json | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($settingsPath, $jsonText, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "フックを登録しました: $settingsPath"

Write-Host ""
Write-Host "完了しました。デスクトップの fukuro-chan ショートカットから起動できます。" -ForegroundColor Green
