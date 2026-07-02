# ============================================================
# ffmpeg 自动工具箱 GUI 版
# ============================================================
param(
    [string]$File1 = "",
    [string]$File2 = ""
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

# ============================================================
# 1. ffmpeg / ffprobe 检测
# ============================================================
$ffmpegPath = ""
$ffprobePath = ""
$ffmpegCmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
$ffprobeCmd = Get-Command ffprobe -ErrorAction SilentlyContinue
if ($ffmpegCmd) { $ffmpegPath = $ffmpegCmd.Source }
if ($ffprobeCmd) { $ffprobePath = $ffprobeCmd.Source }
if (-not $ffmpegPath -or -not $ffprobePath) {
    [System.Windows.Forms.MessageBox]::Show(
        "未找到 ffmpeg / ffprobe，请确保已安装并加入系统 PATH",
        "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}

# ============================================================
# 2. 暗色主题颜色常量
# ============================================================
$C_BG   = [System.Drawing.Color]::FromArgb(18, 19, 22)
$C_BG2  = [System.Drawing.Color]::FromArgb(31, 33, 37)
$C_BG3  = [System.Drawing.Color]::FromArgb(42, 45, 51)
$C_FG   = [System.Drawing.Color]::FromArgb(235, 237, 240)
$C_MUTED = [System.Drawing.Color]::FromArgb(154, 161, 171)
$C_ACC  = [System.Drawing.Color]::FromArgb(54, 130, 205)
$C_ACCH = [System.Drawing.Color]::FromArgb(72, 146, 226)
$C_BRD  = [System.Drawing.Color]::FromArgb(62, 67, 75)
$C_CON  = [System.Drawing.Color]::FromArgb(118, 201, 144)
$C_WARN = [System.Drawing.Color]::FromArgb(236, 176, 82)
$C_OK   = [System.Drawing.Color]::FromArgb(113, 214, 148)
$C_PROG = [System.Drawing.Color]::FromArgb(91, 189, 255)
$C_DANGER = [System.Drawing.Color]::FromArgb(191, 76, 76)
$FONT_UI  = "Microsoft YaHei"
$FONT_MONO = "Consolas"

# ============================================================
# 3. 全局状态
# ============================================================
$Script:CurrentFile = ""
$Script:SecondFile = ""
$Script:CancelRequested = $false
$Script:IsProcessing = $false
$Script:LastWasProgress = $false
$Script:ProgressLineStart = 0
$Script:CurrentFileInfo = ""
$Script:ActionButtons = @()
$Script:SecondaryButtons = @()

# ============================================================
# 4. 工具函数
# ============================================================
function Write-Console {
    param([string]$Text, $Color = $C_CON)
    if ($Script:LastWasProgress) {
        $rtb.Select($rtb.TextLength, 0)
        $rtb.AppendText("`r`n")
        $Script:LastWasProgress = $false
    }
    $rtb.Select($rtb.TextLength, 0)
    $rtb.SelectionColor = $Color
    $rtb.AppendText($Text + "`r`n")
    $rtb.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Write-ProgressLine {
    param([string]$Text)
    if (-not $Script:LastWasProgress) {
        $Script:ProgressLineStart = $rtb.TextLength
        $Script:LastWasProgress = $true
    } else {
        $rtb.Select($Script:ProgressLineStart, $rtb.TextLength - $Script:ProgressLineStart)
    }
    $rtb.SelectionColor = $C_PROG
    $rtb.SelectedText = $Text
    $rtb.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Write-Info  { param([string]$T) Write-Console $T $C_FG }
function Write-Warn  { param([string]$T) Write-Console $T $C_WARN }
function Write-Success { param([string]$T) Write-Console $T $C_OK }
function Clear-Console { $rtb.Clear(); $Script:LastWasProgress = $false }

function Set-ButtonVisual {
    param(
        [System.Windows.Forms.Button]$Button,
        [bool]$Enabled,
        [bool]$Danger = $false
    )
    $Button.Enabled = $Enabled
    if ($Enabled) {
        $Button.BackColor = if ($Danger) { $C_DANGER } else { $C_BG3 }
        $Button.ForeColor = $C_FG
        $Button.FlatAppearance.BorderColor = if ($Danger) { $C_DANGER } else { $C_BRD }
    } else {
        $Button.BackColor = $C_BG2
        $Button.ForeColor = $C_MUTED
        $Button.FlatAppearance.BorderColor = $C_BRD
    }
}

function Lock-UI {
    $Script:IsProcessing = $true
    $Script:CancelRequested = $false
    foreach ($btn in ($Script:ActionButtons + $Script:SecondaryButtons)) {
        Set-ButtonVisual $btn $false
    }
    if ($btnCancel) { Set-ButtonVisual $btnCancel $true $true }
    $pnlDrop.BackColor = $C_BG2
    $lblDropHint.Text = "文件已锁定"
    $lblFileMeta.ForeColor = $C_WARN
}

function Unlock-UI {
    $Script:IsProcessing = $false
    foreach ($btn in $Script:ActionButtons) {
        Set-ButtonVisual $btn $true
    }
    foreach ($btn in $Script:SecondaryButtons) {
        Set-ButtonVisual $btn $true
    }
    if ($btnCancel) { Set-ButtonVisual $btnCancel $false $true }
    $pnlDrop.BackColor = $C_BG2
    Update-FileLabel
}

function Show-FileDialog {
    param([string]$Title, [string]$Filter = "All|*.*")
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = $Title
    $dlg.Filter = $Filter
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dlg.FileName
    }
    return ""
}

function Update-FileLabel {
    if ($Script:CurrentFile) {
        $lblFileName.Text = Split-Path $Script:CurrentFile -Leaf
        $meta = if ($Script:CurrentFileInfo) { $Script:CurrentFileInfo } else { "视频参数将在拖入后显示" }
        if ($Script:SecondFile) { $meta = "$meta    对比: $(Split-Path $Script:SecondFile -Leaf)" }
        $lblFileMeta.Text = $meta
        $lblFileName.ForeColor = $C_FG
        $lblFileMeta.ForeColor = $C_MUTED
    } else {
        $lblFileName.Text = "未选择视频文件"
        $lblFileMeta.Text = "拖入文件后可进行转换、分析、对比或字幕处理"
        $lblFileName.ForeColor = $C_MUTED
        $lblFileMeta.ForeColor = $C_MUTED
    }
}

function Get-VideoInfo {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
    $output = cmd /c "$ffprobePath -v error -select_streams v:0 -show_entries stream=bit_rate,width,height,r_frame_rate -of default=noprint_wrappers=1 `"$Path`" 2>&1"
    $w = $h = $fps = $br = ""
    foreach ($line in $output) {
        if ($line -match "width=(\d+)")  { $w = $matches[1] }
        if ($line -match "height=(\d+)") { $h = $matches[1] }
        if ($line -match "r_frame_rate=(\d+)/(\d+)" -and [int]$matches[2] -ne 0) { $fps = [math]::Round([int]$matches[1] / [int]$matches[2], 0) }
        if ($line -match "bit_rate=(\d+)") { $br = "$([math]::Round([long]$matches[1] / 1000))k" }
    }
    return "${w}x${h}  ${fps}fps  ${br}"
}

function Get-VideoDuration {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return 0 }
    $durOutput = cmd /c "$ffprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 `"$Path`" 2>&1"
    if ($durOutput -match "([\d\.]+)") {
        return [double]::Parse($matches[1], [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return 0
}

function Invoke-FFmpeg {
    param([string]$Arguments, [double]$TotalSeconds = 0)
    $resultList = New-Object System.Collections.Generic.List[string]

    Lock-UI
    $lblStatus.Text = ""
    [System.Windows.Forms.Application]::DoEvents()
    
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo.FileName = $ffmpegPath
    $proc.StartInfo.Arguments = "-hide_banner " + $Arguments
    $proc.StartInfo.UseShellExecute = $false
    $proc.StartInfo.RedirectStandardError = $true
    $proc.StartInfo.CreateNoWindow = $true
    $proc.StartInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    
    try { $proc.Start() | Out-Null } catch { Write-Warn "启动失败: $_"; Unlock-UI; return $null }

    $stderr = $proc.StandardError
    $startTime = Get-Date
    $animFrames = @("|", "/", "-", "\")
    $animIndex = 0
    $lastUpdate = [DateTime]::MinValue
    $readFailed = $false

    while ($true) {
        if ($Script:CancelRequested) {
            Write-Warn "`n[!] 用户取消了任务！正在终止进程..."
            try { $proc.Kill() } catch {}
            break
        }

        # Keep one asynchronous read pending. FFmpeg can be silent for a while
        # during muxing, so silence must not be treated as a crashed process.
        $readTask = $stderr.ReadLineAsync()
        while (-not $readTask.IsCompleted) {
            [System.Windows.Forms.Application]::DoEvents()
            if ($Script:CancelRequested) {
                Write-Warn "`n[!] 用户取消了任务！正在终止进程..."
                try { $proc.Kill() } catch {}
                break
            }
            Start-Sleep -Milliseconds 50
        }

        if ($Script:CancelRequested) { break }

        try {
            $line = $readTask.GetAwaiter().GetResult()
        } catch {
            $readFailed = $true
            Write-Warn "读取 ffmpeg 输出失败: $_"
            break
        }

        if ($null -eq $line) { break }
        $line = $line.Trim()
        if ($line -eq "") { continue }

        $resultList.Add($line)

        if ($line -match "time=(\d{2}):(\d{2}):(\d{2}\.\d+)") {
            $now = Get-Date
            if (($now - $lastUpdate).TotalMilliseconds -gt 100) {
                $lastUpdate = $now
                $h = [double]$matches[1]; $m = [double]$matches[2]; $s = [double]$matches[3]
                $curSec = $h * 3600 + $m * 60 + $s

                $speedStr = "--"
                if ($line -match "speed=\s*([\d\.]+)x") { $speedStr = $matches[1] + "x" }

                $realElapsed = (Get-Date) - $startTime
                $elapsedStr = "{0:d2}:{1:d2}:{2:d2}" -f $realElapsed.Hours, $realElapsed.Minutes, $realElapsed.Seconds

                if ($TotalSeconds -gt 0) {
                    $percent = ($curSec / $TotalSeconds) * 100
                    if ($percent -gt 100) { $percent = 100 }

                    $remStr = "--:--:--"
                    if ($curSec -gt 0 -and $percent -lt 100) {
                        $remSec = ($realElapsed.TotalSeconds / $curSec) * ($TotalSeconds - $curSec)
                        $remSpan = [TimeSpan]::FromSeconds($remSec)
                        $remStr = "{0:d2}:{1:d2}:{2:d2}" -f $remSpan.Hours, $remSpan.Minutes, $remSpan.Seconds
                    }

                    $filled = [math]::Floor(($percent / 100) * 30)
                    if ($filled -lt 0) { $filled = 0 }
                    if ($filled -gt 30) { $filled = 30 }
                    $empty = 30 - $filled
                    $bar = ("█" * $filled) + ("░" * $empty)

                    Write-ProgressLine "▶ [$bar] $([math]::Round($percent,1))% │ 耗时 $elapsedStr │ 剩余 $remStr │ 速度 $speedStr"
                } else {
                    $anim = $animFrames[$animIndex % 4]
                    $animIndex++
                    Write-ProgressLine "$anim 处理中... │ 媒体时间 $([math]::Round($curSec,1))s │ 耗时 $elapsedStr │ 速度 $speedStr"
                }
            }
        } elseif ($line -match "error|failed" -and $line -notmatch "showspectrumpic") {
            Write-Warn $line
        }
    }

    if (-not $proc.HasExited) {
        try { $proc.WaitForExit() } catch {}
    }
    $exitCode = if ($proc.HasExited) { $proc.ExitCode } else { $null }
    $success = -not $Script:CancelRequested -and -not $readFailed -and $null -ne $exitCode -and $exitCode -eq 0

    # Only report completion after ffmpeg has really exited successfully.
    if ($success -and $TotalSeconds -gt 0 -and $Script:LastWasProgress) {
        $realElapsed = (Get-Date) - $startTime
        $elapsedStr = "{0:d2}:{1:d2}:{2:d2}" -f $realElapsed.Hours, $realElapsed.Minutes, $realElapsed.Seconds
        $bar = "█" * 30
        Write-ProgressLine "▶ [$bar] 100% │ 耗时 $elapsedStr │ 剩余 00:00:00 │ 完成"
    }

    if ($Script:LastWasProgress) {
        $rtb.Select($rtb.TextLength, 0)
        $rtb.AppendText("`r`n")
        $Script:LastWasProgress = $false
    }

    if (-not $Script:CancelRequested -and -not $success) {
        $codeText = if ($null -eq $exitCode) { "无法取得退出码" } else { "代码: $exitCode" }
        Write-Warn "`n[X] ffmpeg 异常退出 ($codeText)"
        $startIdx = [math]::Max(0, $resultList.Count - 15)
        for ($i = $startIdx; $i -lt $resultList.Count; $i++) {
            Write-Console $resultList[$i] $C_BRD
        }
        $lblStatus.Text = ""
        Unlock-UI
        [System.Windows.Forms.Application]::DoEvents()
        return $null
    }

    $lblStatus.Text = ""
    Unlock-UI
    [System.Windows.Forms.Application]::DoEvents()
    if ($Script:CancelRequested) { return $null }
    return $resultList
}

# ============================================================
# 5. ffmpeg 功能函数
# ============================================================

function Convert-LowLoss {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { Write-Warn "文件不存在"; return }
    $outFile = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($Path), [System.IO.Path]::GetFileNameWithoutExtension($Path) + "_lowloss.mp4")
    Write-Info "[格式转换: 低损耗]"
    $dur = Get-VideoDuration $Path
    $res = Invoke-FFmpeg "-y -i `"$Path`" -c:v libx264 -crf 18 -preset slow -c:a aac -b:a 320k `"$outFile`"" $dur
    if ($null -ne $res -and -not $Script:CancelRequested) { Write-Success "完成: $outFile" }
}

function Convert-Normal {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { Write-Warn "文件不存在"; return }
    $outFile = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($Path), [System.IO.Path]::GetFileNameWithoutExtension($Path) + "_normal.mp4")
    Write-Info "[格式转换: 普通]"
    $dur = Get-VideoDuration $Path
    $res = Invoke-FFmpeg "-y -i `"$Path`" -c:v libx264 -crf 18 -c:a aac -b:a 192k `"$outFile`"" $dur
    if ($null -ne $res -and -not $Script:CancelRequested) { Write-Success "完成: $outFile" }
}

function Test-Probe {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { Write-Warn "文件不存在"; return }
    Write-Info "[核对参数]"
    $output = cmd /c "$ffprobePath -v error -select_streams v:0 -show_entries stream=bit_rate,width,height,r_frame_rate -of default=noprint_wrappers=1 `"$Path`" 2>&1"
    foreach ($line in $output) { Write-Console $line }
}

function New-Spectrum {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { Write-Warn "文件不存在"; return }
    $outFile = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($Path), [System.IO.Path]::GetFileNameWithoutExtension($Path) + "_spectrum.jpg")
    Write-Info "[生成频谱]"
    $res = Invoke-FFmpeg "-y -i `"$Path`" -lavfi `"showspectrumpic=s=1920x1080:color=magma:scale=log:legend=1`" -frames:v 1 -update 1 `"$outFile`""
    if ($null -ne $res -and -not $Script:CancelRequested) { Write-Success "完成: $outFile" }
}

function Compare-SSIM {
    param([string]$f1, [string]$f2)
    if (-not (Test-Path -LiteralPath $f1) -or -not (Test-Path -LiteralPath $f2)) { Write-Warn "请确保两个文件都已选择"; return }
    Write-Info "[SSIM 对比] (时间可能较长，请耐心等待...)"
    $dur = Get-VideoDuration $f1
    $output = Invoke-FFmpeg "-y -i `"$f1`" -i `"$f2`" -filter_complex ssim -f null -" $dur
    if ($null -eq $output -or $Script:CancelRequested) { return }
    $line = $output | Where-Object { $_ -match "All:(\d\.\d+)" } | Select-Object -Last 1
    if ($line -match "All:(\d\.\d+)") {
        $val = [double]::Parse($matches[1], [System.Globalization.CultureInfo]::InvariantCulture)
        Write-Success "还原度: $( ($val * 100).ToString('F4') ) %"
    } else {
        Write-Warn "无法解析分值"
    }
}

function Compare-Diff {
    param([string]$f1, [string]$f2)
    if (-not (Test-Path -LiteralPath $f1) -or -not (Test-Path -LiteralPath $f2)) { Write-Warn "请确保两个文件都已选择"; return }
    $outFile = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($f1), "difference.jpg")
    Write-Info "[生成差值图]"
    $res = Invoke-FFmpeg "-y -i `"$f1`" -i `"$f2`" -filter_complex `"blend=all_mode=difference,lutyuv=y=val*10:u=val:v=val`" -frames:v 1 -q:v 2 -update 1 `"$outFile`""
    if ($null -ne $res -and -not $Script:CancelRequested) { Write-Success "已保存: $outFile" }
}

function Compare-Quality {
    param([string]$f1, [string]$f2)
    if (-not (Test-Path -LiteralPath $f1) -or -not (Test-Path -LiteralPath $f2)) { Write-Warn "请确保两个文件都已选择"; return }
    Write-Info "[全方位质量对比]"
    Write-Info "1/2 计算 SSIM..."
    $dur = Get-VideoDuration $f1
    $output = Invoke-FFmpeg "-y -i `"$f1`" -i `"$f2`" -filter_complex ssim -f null -" $dur
    if ($Script:CancelRequested) { return }
    $scoreText = "失败"
    $line = $output | Where-Object { $_ -match "All:(\d\.\d+)" } | Select-Object -Last 1
    if ($line -match "All:(\d\.\d+)") {
        $val = [double]::Parse($matches[1], [System.Globalization.CultureInfo]::InvariantCulture)
        $scoreText = "$( ($val * 100).ToString('F4') ) %"
    }
    
    $outFile = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($f1), "quality_report.jpg")
    Write-Info "2/2 生成差值图..."
    $res = Invoke-FFmpeg "-y -i `"$f1`" -i `"$f2`" -filter_complex `"blend=all_mode=difference,lutyuv=y=val*10:u=val:v=val`" -frames:v 1 -q:v 2 -update 1 `"$outFile`""
    if ($null -ne $res -and -not $Script:CancelRequested) {
        Write-Success "结果: SSIM $scoreText"
        Write-Success "图片: $outFile"
    }
}

function Convert-Subtitle {
    param([string]$VideoPath)
    if (-not (Test-Path -LiteralPath $VideoPath)) { Write-Warn "视频文件不存在"; return }
    
    $subFile = Show-FileDialog "选择字幕文件" "字幕文件|*.srt;*.ass|所有文件|*.*"
    if (-not $subFile) { return }
    
    $fontName = "Microsoft YaHei"
    $fontInput = [Microsoft.VisualBasic.Interaction]::InputBox("请输入字体名称", "字体设置", "Microsoft YaHei")
    if ($fontInput) { $fontName = $fontInput }
    
    Write-Info "[嵌入硬字幕]"
    $tmpDir = [System.IO.Path]::Combine($env:TEMP, "ffmpeg_toolbox_sub_" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

    try {
        $ext = [System.IO.Path]::GetExtension($subFile).ToLower()
        $localSub = [System.IO.Path]::Combine($tmpDir, "subtitle$ext")
        Copy-Item -LiteralPath $subFile -Destination $localSub -Force

        if ($ext -eq ".srt") {
            Write-Info "SRT -> ASS 转换..."
            $assLocal = [System.IO.Path]::Combine($tmpDir, "subtitle.ass")
            $convertOutput = & $ffmpegPath -hide_banner -loglevel error -y -sub_charenc UTF-8 -i $localSub $assLocal 2>&1
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $assLocal)) {
                Write-Warn "SRT 转 ASS 失败，任务已停止"
                foreach ($line in $convertOutput) { Write-Console $line $C_BRD }
                return
            }
            $assContent = Get-Content -LiteralPath $assLocal -Raw -Encoding UTF8
            $assContent = $assContent -replace '(?<=Style: Default,)[^,]+', $fontName
            Set-Content -LiteralPath $assLocal -Value $assContent -Encoding UTF8
            $localSub = $assLocal
        } elseif ($ext -eq ".ass") {
            $assContent = Get-Content -LiteralPath $localSub -Raw -Encoding UTF8
            $assContent = $assContent -replace '(?<=Style: Default,)[^,]+', $fontName
            Set-Content -LiteralPath $localSub -Value $assContent -Encoding UTF8
        }

        # Keep MP4/MOV-family inputs in a compatible container. Other inputs use
        # MKV so every source audio track can be copied without a lossy conversion.
        $videoExt = [System.IO.Path]::GetExtension($VideoPath).ToLower()
        $outputExt = switch ($videoExt) {
            ".mp4" { ".mp4" }
            ".m4v" { ".mp4" }
            ".mov" { ".mov" }
            default { ".mkv" }
        }
        $outFile = [System.IO.Path]::Combine(
            [System.IO.Path]::GetDirectoryName($VideoPath),
            [System.IO.Path]::GetFileNameWithoutExtension($VideoPath) + "_sub" + $outputExt
        )

        Write-Info "压制字幕 (CRF 16 高质量，兼容像素格式，全部音轨原样复制)..."
        $escapedSub = $localSub -replace '\\', '/' -replace ':', '\:' -replace "'", "\'"
        $dur = Get-VideoDuration $VideoPath
        $arguments = "-y -i `"$VideoPath`" -map 0:v:0 -map 0:a? -map_metadata 0 -map_chapters 0 " +
                     "-vf `"subtitles='$escapedSub'`" -c:v libx264 -crf 16 -preset slow -pix_fmt yuv420p " +
                     "-c:a copy `"$outFile`""
        $res = Invoke-FFmpeg $arguments $dur

        if ($null -ne $res -and -not $Script:CancelRequested) { Write-Success "完成: $outFile" }
    } finally {
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================
# 6. 构建 GUI
# ============================================================
# 标题栏暗色 (Windows 10 1809+ / 11)
$dwm = @"
using System;
using System.Runtime.InteropServices;
public class DwmApi {
    [DllImport("dwmapi.dll", PreserveSig = true)]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
}
"@
Add-Type $dwm
$DWMWA_USE_DARK_MODE = if ([Environment]::OSVersion.Version.Build -ge 22000) { 20 } else { 19 }

$form = New-Object System.Windows.Forms.Form
$form.Text = "ffmpeg 自动工具箱"
$form.ClientSize = New-Object System.Drawing.Size(920, 680)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = $C_BG
$form.ForeColor = $C_FG
$form.Font = New-Object System.Drawing.Font($FONT_UI, 9)
$form.AllowDrop = $true
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false

function New-UiLabel {
    param(
        [System.Windows.Forms.Control]$Parent,
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W,
        [int]$H,
        [System.Drawing.Font]$Font,
        [System.Drawing.Color]$Color,
        [System.Drawing.ContentAlignment]$Align = [System.Drawing.ContentAlignment]::MiddleLeft
    )
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.AutoSize = $false
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($W, $H)
    $label.Font = $Font
    $label.ForeColor = $Color
    $label.TextAlign = $Align
    $label.AutoEllipsis = $true
    $Parent.Controls.Add($label)
    return $label
}

function New-SectionPanel {
    param([string]$Title, [int]$X, [int]$Y, [int]$W, [int]$H)
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point($X, $Y)
    $panel.Size = New-Object System.Drawing.Size($W, $H)
    $panel.BackColor = $C_BG2
    $panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $form.Controls.Add($panel)
    New-UiLabel $panel $Title 16 10 ($W - 32) 22 (New-Object System.Drawing.Font($FONT_UI, 9, [System.Drawing.FontStyle]::Bold)) $C_FG | Out-Null
    return $panel
}

function New-UiButton {
    param(
        [System.Windows.Forms.Control]$Parent,
        [string]$Text,
        [int]$X,
        [int]$Y,
        [scriptblock]$Action,
        [int]$W = 170,
        [int]$H = 34,
        [ValidateSet("Action", "Secondary", "Danger")][string]$Kind = "Action"
    )
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Object System.Drawing.Point($X, $Y)
    $btn.Size = New-Object System.Drawing.Size($W, $H)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.BackColor = if ($Kind -eq "Danger") { $C_BG2 } else { $C_BG3 }
    $btn.ForeColor = if ($Kind -eq "Danger") { $C_MUTED } else { $C_FG }
    $btn.Font = New-Object System.Drawing.Font($FONT_UI, 9)
    $btn.FlatAppearance.BorderColor = $C_BRD
    $btn.FlatAppearance.MouseOverBackColor = if ($Kind -eq "Danger") { $C_DANGER } else { $C_ACCH }
    $btn.FlatAppearance.MouseDownBackColor = if ($Kind -eq "Danger") { $C_DANGER } else { $C_ACC }
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.Add_Click($Action)
    $Parent.Controls.Add($btn)
    if ($Kind -eq "Action") { $Script:ActionButtons += $btn } else { $Script:SecondaryButtons += $btn }
    return $btn
}

# ---- 顶部标题 ----
New-UiLabel $form "ffmpeg 自动工具箱" 24 16 360 30 (New-Object System.Drawing.Font($FONT_UI, 15, [System.Drawing.FontStyle]::Bold)) $C_FG | Out-Null
New-UiLabel $form "视频转换、质量检查、频谱分析、硬字幕压制" 26 48 520 22 (New-Object System.Drawing.Font($FONT_UI, 9)) $C_MUTED | Out-Null

# ---- 文件工作区 ----
$pnlDrop = New-Object System.Windows.Forms.Panel
$pnlDrop.Size = New-Object System.Drawing.Size(872, 98)
$pnlDrop.Location = New-Object System.Drawing.Point(24, 84)
$pnlDrop.BackColor = $C_BG2
$pnlDrop.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$pnlDrop.AllowDrop = $true
$form.Controls.Add($pnlDrop)

$lblDropHint = New-UiLabel $pnlDrop "当前文件" 20 14 180 22 (New-Object System.Drawing.Font($FONT_UI, 9, [System.Drawing.FontStyle]::Bold)) $C_FG
$lblFileName = New-UiLabel $pnlDrop "未选择视频文件" 20 38 810 28 (New-Object System.Drawing.Font($FONT_UI, 12, [System.Drawing.FontStyle]::Bold)) $C_MUTED
$lblFileMeta = New-UiLabel $pnlDrop "拖入文件后可进行转换、分析、对比或字幕处理" 20 68 810 20 (New-Object System.Drawing.Font($FONT_UI, 9)) $C_MUTED

# 拖拽事件
function Invoke-Drop {
    if ($Script:IsProcessing) { return }
    $files = $_.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
    if ($files.Count -gt 0) {
        $Script:CurrentFile = $files[0]
        $Script:SecondFile = if ($files.Count -gt 1) { $files[1] } else { "" }
        $Script:CurrentFileInfo = Get-VideoInfo $Script:CurrentFile
        Update-FileLabel
    }
}

$pnlDrop.Add_DragEnter({ $_.Effect = [System.Windows.Forms.DragDropEffects]::Copy })
$pnlDrop.Add_DragDrop({ Invoke-Drop })
$form.Add_DragEnter({ $_.Effect = [System.Windows.Forms.DragDropEffects]::Copy })
$form.Add_DragDrop({ Invoke-Drop })

# ---- 功能分组 ----
$grpConvert = New-SectionPanel "格式转换" 24 202 424 92
New-UiButton $grpConvert "低损耗 MP4" 16 44 { Clear-Console; if (-not $Script:CurrentFile) { Write-Warn "请先选择文件"; return }; Convert-LowLoss $Script:CurrentFile } 188 34 | Out-Null
New-UiButton $grpConvert "普通 MP4" 220 44 { Clear-Console; if (-not $Script:CurrentFile) { Write-Warn "请先选择文件"; return }; Convert-Normal $Script:CurrentFile } 188 34 | Out-Null

$grpInspect = New-SectionPanel "媒体分析" 472 202 424 92
New-UiButton $grpInspect "参数核对" 16 44 { Clear-Console; if (-not $Script:CurrentFile) { Write-Warn "请先选择文件"; return }; Test-Probe $Script:CurrentFile } 188 34 | Out-Null
New-UiButton $grpInspect "生成频谱" 220 44 { Clear-Console; if (-not $Script:CurrentFile) { Write-Warn "请先选择文件"; return }; New-Spectrum $Script:CurrentFile } 188 34 | Out-Null

$grpCompare = New-SectionPanel "质量对比" 24 310 584 92
New-UiButton $grpCompare "SSIM 对比" 16 44 { Clear-Console; if (-not $Script:CurrentFile) { Write-Warn "请先选择文件"; return }; if (-not $Script:SecondFile) { $s = Show-FileDialog "选择对比文件" "视频|*.mp4;*.webm;*.mkv;*.avi|所有|*.*"; if ($s) { $Script:SecondFile = $s; Update-FileLabel } else { Write-Warn "请选择对比文件"; return } }; Compare-SSIM $Script:CurrentFile $Script:SecondFile } 170 34 | Out-Null
New-UiButton $grpCompare "差值图" 202 44 { Clear-Console; if (-not $Script:CurrentFile) { Write-Warn "请先选择文件"; return }; if (-not $Script:SecondFile) { $s = Show-FileDialog "选择对比文件" "视频|*.mp4;*.webm;*.mkv;*.avi|所有|*.*"; if ($s) { $Script:SecondFile = $s; Update-FileLabel } else { Write-Warn "请选择对比文件"; return } }; Compare-Diff $Script:CurrentFile $Script:SecondFile } 170 34 | Out-Null
New-UiButton $grpCompare "质量报告" 388 44 { Clear-Console; if (-not $Script:CurrentFile) { Write-Warn "请先选择文件"; return }; if (-not $Script:SecondFile) { $s = Show-FileDialog "选择对比文件" "视频|*.mp4;*.webm;*.mkv;*.avi|所有|*.*"; if ($s) { $Script:SecondFile = $s; Update-FileLabel } else { Write-Warn "请选择对比文件"; return } }; Compare-Quality $Script:CurrentFile $Script:SecondFile } 176 34 | Out-Null

$grpSubtitle = New-SectionPanel "字幕处理" 632 310 264 92
New-UiButton $grpSubtitle "嵌入硬字幕" 16 44 { Clear-Console; if (-not $Script:CurrentFile) { Write-Warn "请先选择文件"; return }; Convert-Subtitle $Script:CurrentFile } 232 34 | Out-Null

# ---- 辅助操作 ----
$btnClearSecond = New-UiButton $form "清除对比文件" 24 418 {
    $Script:SecondFile = ""
    Update-FileLabel
    Write-Info "对比文件已清除"
} 160 30 "Secondary"

$btnCancel = New-UiButton $form "取消当前任务" 198 418 {
    $Script:CancelRequested = $true
} 160 30 "Danger"
$btnCancel.Name = "btnCancel"
Set-ButtonVisual $btnCancel $false $true

# ---- 控制台输出 ----
$pnlLog = New-Object System.Windows.Forms.Panel
$pnlLog.Location = New-Object System.Drawing.Point(24, 464)
$pnlLog.Size = New-Object System.Drawing.Size(872, 192)
$pnlLog.BackColor = $C_BG2
$pnlLog.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($pnlLog)

New-UiLabel $pnlLog "任务日志" 16 10 180 22 (New-Object System.Drawing.Font($FONT_UI, 9, [System.Drawing.FontStyle]::Bold)) $C_FG | Out-Null

$rtb = New-Object System.Windows.Forms.RichTextBox
$rtb.Location = New-Object System.Drawing.Point(16, 40)
$rtb.Size = New-Object System.Drawing.Size(840, 136)
$rtb.BackColor = [System.Drawing.Color]::FromArgb(12, 13, 15)
$rtb.ForeColor = $C_CON
$rtb.Font = New-Object System.Drawing.Font($FONT_MONO, 9)
$rtb.ReadOnly = $true
$rtb.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtb.WordWrap = $false
$pnlLog.Controls.Add($rtb)

# 保留隐藏状态标签，避免任务函数里的状态赋值影响界面。
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = ""
$lblStatus.Visible = $false
# ============================================================
# 7. 入口
# ============================================================
if ($File1 -and (Test-Path -LiteralPath $File1)) {
    $Script:CurrentFile = $File1
    if ($File2 -and (Test-Path -LiteralPath $File2)) { $Script:SecondFile = $File2 }
}

[System.Windows.Forms.Application]::EnableVisualStyles()
Update-FileLabel


# 标题栏暗色 (Shown 事件触发)
$form.Add_Shown({
    $darkVal = 1
    [DwmApi]::DwmSetWindowAttribute($form.Handle, $DWMWA_USE_DARK_MODE, [ref]$darkVal, 4)
})

$form.ShowDialog() | Out-Null
