param(
    [string]$File1 = "",
    [string]$File2 = ""
)

# 适配日语系统环境，强制使用 UTF8 编码显示中文
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "ffmpeg 自动工具箱"

# 自动检测 ffmpeg / ffprobe 路径
$ffmpegPath = ""
$ffprobePath = ""

# 优先从系统 PATH 中查找
$ffmpegCmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
$ffprobeCmd = Get-Command ffprobe -ErrorAction SilentlyContinue
if ($ffmpegCmd) { $ffmpegPath = $ffmpegCmd.Source }
if ($ffprobeCmd) { $ffprobePath = $ffprobeCmd.Source }

# PATH 中没找到则让用户手动输入
if (-not $ffmpegPath) {
    Write-Host "`n未在系统 PATH 中找到 ffmpeg，请手动输入 ffmpeg.exe 的完整路径" -ForegroundColor Yellow
    $inputPath = Read-Host "ffmpeg.exe 路径"
    if (Test-Path -LiteralPath $inputPath) {
        $ffmpegPath = $inputPath
        $ffprobePath = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($inputPath), "ffprobe.exe")
        if (-not (Test-Path -LiteralPath $ffprobePath)) { $ffprobePath = "" }
    }
}

if (-not $ffprobePath) {
    Write-Host "`n未在系统 PATH 中找到 ffprobe，请手动输入 ffprobe.exe 的完整路径" -ForegroundColor Yellow
    $inputPath = Read-Host "ffprobe.exe 路径"
    if (Test-Path -LiteralPath $inputPath) { $ffprobePath = $inputPath }
}

if (-not $ffmpegPath -or -not $ffprobePath) {
    Write-Host "错误：未找到 ffmpeg 或 ffprobe，请确保已安装 ffmpeg" -ForegroundColor Red
    Write-Host "你可以从 https://ffmpeg.org/download.html 下载安装" -ForegroundColor Cyan
    pause
    exit 1
}

# 处理传入的文件路径（使用 LiteralPath 防止括号报错）
$DraggedFiles = @()
if ($File1 -and (Test-Path -LiteralPath $File1)) { $DraggedFiles += $File1 }
if ($File2 -and (Test-Path -LiteralPath $File2)) { $DraggedFiles += $File2 }

function Get-InputFile {
    param([string]$InputPath, [string]$Prompt)
    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        Write-Host ""
        $InputPath = Read-Host $Prompt
    }
    if ($null -eq $InputPath) { return "" }
    return $InputPath.Trim('"')
}

function Wait-UserAction {
    Write-Host "`n请按任意键继续..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    if ($DraggedFiles.Length -gt 0) {
        Show-DragMenu
    } else {
        Show-MainMenu
    }
}

function Show-MainMenu {
    Clear-Host
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host "                 ffmpeg 自动工具箱" -ForegroundColor Green
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. 格式转换: webm转mp4（低损耗）"
    Write-Host "  2. 格式转换: webm转mp4（普通）"
    Write-Host "  3. 核对分辨率、码率等基础参数"
    Write-Host "  4. 分色带刻度频谱"
    Write-Host "  5. SSIM 还原百分比 (双文件对比)"
    Write-Host "  6. 差值图 (高亮强化, 双文件对比)"
    Write-Host "  7. 全方位质量对比 (分值+图)"
    Write-Host ""
    Write-Host "  0. 退出"
    Write-Host "====================================================" -ForegroundColor Cyan
    
    $choice = Read-Host "请输入功能编号 (0-7)"
    
    switch ($choice) {
        "1" { Convert-LowLoss }
        "2" { Convert-Normal }
        "3" { Test-Probe }
        "4" { New-Spectrum }
        "5" { Compare-SSIM }
        "6" { Compare-Diff }
        "7" { Compare-Quality }
        "0" { exit }
        default { Show-MainMenu }
    }
}

function Show-DragMenu {
    $f1 = if ($DraggedFiles.Length -gt 0) { $DraggedFiles[0] } else { "" }
    $f2 = if ($DraggedFiles.Length -gt 1) { $DraggedFiles[1] } else { "" }

    Clear-Host
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host "  检测到拖入的文件: " -ForegroundColor Green
    foreach ($f in $DraggedFiles) { Write-Host "  $f" }
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. 格式转换: webm转mp4（低损耗）"
    Write-Host "  2. 格式转换: webm转mp4（普通）"
    Write-Host "  3. 核对基础参数"
    Write-Host "  4. 分色带刻度频谱"
    Write-Host "  5. SSIM 还原百分比 (需对比文件)"
    Write-Host "  6. 差值图 (高亮强化)"
    Write-Host "  7. 全方位质量对比"
    Write-Host ""
    Write-Host "  0. 退出"
    Write-Host "====================================================" -ForegroundColor Cyan

    $choice = Read-Host "请输入功能编号 (0-7)"
    
    switch ($choice) {
        "1" { Convert-LowLoss $f1 }
        "2" { Convert-Normal $f1 }
        "3" { Test-Probe $f1 }
        "4" { New-Spectrum $f1 }
        "5" { Compare-SSIM $f1 $f2 }
        "6" { Compare-Diff $f1 $f2 }
        "7" { Compare-Quality $f1 $f2 }
        "0" { exit }
        default { Show-DragMenu }
    }
}

function Convert-LowLoss {
    param([string]$InputPath = "")
    Write-Host "`n[格式转换: 低损耗]" -ForegroundColor Yellow
    $file = Get-InputFile $InputPath "请输入路径"
    if (-not (Test-Path -LiteralPath $file)) { Write-Host "文件不存在"; Wait-UserAction; return }
    $outFile = [System.IO.Path]::ChangeExtension($file, "_lowloss.mp4")
    & $ffmpegPath -i $file -c:v libx264 -crf 18 -preset slow -c:a aac -b:a 320k $outFile
    Write-Host "`n完成！" -ForegroundColor Green
    Wait-UserAction
}

function Convert-Normal {
    param([string]$InputPath = "")
    Write-Host "`n[格式转换: 普通]" -ForegroundColor Yellow
    $file = Get-InputFile $InputPath "请输入路径"
    if (-not (Test-Path -LiteralPath $file)) { Write-Host "文件不存在"; Wait-UserAction; return }
    $outFile = [System.IO.Path]::ChangeExtension($file, "_normal.mp4")
    & $ffmpegPath -i $file -c:v libx264 -crf 18 -c:a aac -b:a 192k $outFile
    Write-Host "`n完成！" -ForegroundColor Green
    Wait-UserAction
}

function Test-Probe {
    param([string]$InputPath = "")
    Write-Host "`n[核对参数]" -ForegroundColor Yellow
    $file = Get-InputFile $InputPath "请输入路径"
    if (-not (Test-Path -LiteralPath $file)) { Write-Host "文件不存在"; Wait-UserAction; return }
    & $ffprobePath -v error -select_streams v:0 -show_entries stream=bit_rate,width,height,r_frame_rate -of default=noprint_wrappers=1 $file
    Wait-UserAction
}

function New-Spectrum {
    param([string]$InputPath = "")
    Write-Host "`n[生成频谱]" -ForegroundColor Yellow
    $file = Get-InputFile $InputPath "请输入路径"
    if (-not (Test-Path -LiteralPath $file)) { Write-Host "文件不存在"; Wait-UserAction; return }
    $outFile = [System.IO.Path]::ChangeExtension($file, "_spectrum.jpg")
    & $ffmpegPath -i $file -lavfi "showspectrumpic=s=1920x1080:color=magma:scale=log:legend=1" $outFile
    Write-Host "`n完成！" -ForegroundColor Green
    Wait-UserAction
}

function Compare-SSIM {
    param([string]$f1_in = "", [string]$f2_in = "")
    Write-Host "`n[SSIM 对比]" -ForegroundColor Yellow
    $f1 = Get-InputFile $f1_in "请输入第一个路径"
    $f2 = Get-InputFile $f2_in "请输入第二个路径"
    if (-not (Test-Path -LiteralPath $f1) -or -not (Test-Path -LiteralPath $f2)) { Write-Host "文件不存在"; Wait-UserAction; return }
    Write-Host "正在计算..."
    $output = & $ffmpegPath -i $f1 -i $f2 -filter_complex ssim -f null - 2>&1
    $line = $output | Where-Object { $_ -match "All:(\d\.\d+)" }
    if ($line -match "All:(\d\.\d+)") {
        $scoreText = $matches[1]
        Write-Host "还原度: $( ([double]::Parse($scoreText, [System.Globalization.CultureInfo]::InvariantCulture) * 100).ToString('F4') ) %" -ForegroundColor Green
    } else {
        Write-Host "无法解析分值" -ForegroundColor Red
    }
    Wait-UserAction
}

function Compare-Diff {
    param([string]$f1_in = "", [string]$f2_in = "")
    Write-Host "`n[生成差值图]" -ForegroundColor Yellow
    $f1 = Get-InputFile $f1_in "请输入第一个路径"
    $f2 = Get-InputFile $f2_in "请输入第二个路径"
    if (-not (Test-Path -LiteralPath $f1) -or -not (Test-Path -LiteralPath $f2)) { Write-Host "文件不存在"; Wait-UserAction; return }
    $outFile = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($f1), "difference.jpg")
    & $ffmpegPath -i $f1 -i $f2 -filter_complex "blend=all_mode=difference,lutyuv=y=val*10:u=val:v=val" -frames:v 1 -q:v 2 -update 1 $outFile
    Write-Host "已保存: $outFile" -ForegroundColor Green
    Wait-UserAction
}

function Compare-Quality {
    param([string]$f1_in = "", [string]$f2_in = "")
    Write-Host "`n[全方位质量对比]" -ForegroundColor Yellow
    $f1 = Get-InputFile $f1_in "请输入第一个路径"
    $f2 = Get-InputFile $f2_in "请输入第二个路径"
    if (-not (Test-Path -LiteralPath $f1) -or -not (Test-Path -LiteralPath $f2)) { Write-Host "文件不存在"; Wait-UserAction; return }
    
    Write-Host "1/2 计算 SSIM..."
    $output = & $ffmpegPath -i $f1 -i $f2 -filter_complex ssim -f null - 2>&1
    $scoreText = "失败"
    if (($output | Where-Object { $_ -match "All:(\d\.\d+)" }) -match "All:(\d\.\d+)") {
        $val = [double]::Parse($matches[1], [System.Globalization.CultureInfo]::InvariantCulture)
        $scoreText = "$( ($val * 100).ToString('F4') ) %"
    }
    
    Write-Host "2/2 生成差值图..."
    $outFile = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($f1), "quality_report.jpg")
    & $ffmpegPath -i $f1 -i $f2 -filter_complex "blend=all_mode=difference,lutyuv=y=val*10:u=val:v=val" -frames:v 1 -q:v 2 -update 1 $outFile
    
    Write-Host "`n结果: SSIM $scoreText" -ForegroundColor Green
    Write-Host "图片: $outFile" -ForegroundColor Green
    Wait-UserAction
}

# 入口
if ($DraggedFiles.Length -gt 0) { Show-DragMenu } else { Show-MainMenu }
