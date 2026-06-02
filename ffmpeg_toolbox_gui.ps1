# ============================================================
# ffmpeg 自动工具箱 GUI 版 (暗色主题)
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
$C_BG   = [System.Drawing.Color]::FromArgb(30, 30, 30)
$C_BG2  = [System.Drawing.Color]::FromArgb(45, 45, 45)
$C_BG3  = [System.Drawing.Color]::FromArgb(60, 60, 60)
$C_FG   = [System.Drawing.Color]::FromArgb(212, 212, 212)
$C_ACC  = [System.Drawing.Color]::FromArgb(0, 122, 204)
$C_ACCH = [System.Drawing.Color]::FromArgb(0, 150, 240)
$C_BRD  = [System.Drawing.Color]::FromArgb(80, 80, 80)
$C_CON  = [System.Drawing.Color]::FromArgb(0, 180, 0)
$C_WARN = [System.Drawing.Color]::FromArgb(255, 180, 0)
$C_OK   = [System.Drawing.Color]::FromArgb(80, 200, 80)
$FONT_UI  = "Microsoft YaHei"
$FONT_MONO = "Consolas"

# ============================================================
# 3. 全局状态
# ============================================================
$Script:CurrentFile = ""
$Script:SecondFile = ""

# ============================================================
# 4. 工具函数
# ============================================================
function Write-Console {
    param([string]$Text, $Color = $C_CON)
    $rtb.Select($rtb.TextLength, 0)
    $rtb.SelectionColor = $Color
    $rtb.AppendText($Text + "`r`n")
    $rtb.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Write-Info  { param([string]$T) Write-Console $T $C_FG }
function Write-Warn  { param([string]$T) Write-Console $T $C_WARN }
function Write-Success { param([string]$T) Write-Console $T $C_OK }
function Clear-Console { $rtb.Clear() }

function Invoke-FFmpeg {
    param([string]$Args)
    $result = cmd /c "$ffmpegPath $Args 2>&1"
    foreach ($line in $result) {
        if ($line -match "error|failed" -and $line -notmatch "showspectrumpic") {
            Write-Warn $line
        } else {
            Write-Console $line
        }
    }
    return $result
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
    $t1 = if ($Script:CurrentFile) { Split-Path $Script:CurrentFile -Leaf } else { "未选择文件" }
    $t2 = if ($Script:SecondFile) { "`n对比: " + (Split-Path $Script:SecondFile -Leaf) } else { "" }
    $lblFile.Text = "文件: $t1$t2"
    $lblFile.ForeColor = if ($Script:CurrentFile) { $C_OK } else { $C_BRD }
}

function Get-VideoInfo {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
    $output = cmd /c "$ffprobePath -v error -select_streams v:0 -show_entries stream=bit_rate,width,height,r_frame_rate -of default=noprint_wrappers=1 `"$Path`" 2>&1"
    $w = $h = $fps = $br = ""
    foreach ($line in $output) {
        if ($line -match "width=(\d+)")  { $w = $matches[1] }
        if ($line -match "height=(\d+)") { $h = $matches[1] }
        if ($line -match "r_frame_rate=(\d+)/(\d+)") { $fps = [math]::Round([int]$matches[1] / [int]$matches[2], 0) }
        if ($line -match "bit_rate=(\d+)") { $br = "$([math]::Round([int]$matches[1] / 1000))k" }
    }
    return "${w}x${h}  ${fps}fps  ${br}"
}

# ============================================================
# 5. ffmpeg 功能函数
# ============================================================

function Convert-LowLoss {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { Write-Warn "文件不存在"; return }
    $outFile = [System.IO.Path]::ChangeExtension($Path, "_lowloss.mp4")
    Write-Info "[格式转换: 低损耗]"
    Invoke-FFmpeg "-y -i `"$Path`" -c:v libx264 -crf 18 -preset slow -c:a aac -b:a 320k `"$outFile`""
    Write-Success "完成: $outFile"
}

function Convert-Normal {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { Write-Warn "文件不存在"; return }
    $outFile = [System.IO.Path]::ChangeExtension($Path, "_normal.mp4")
    Write-Info "[格式转换: 普通]"
    Invoke-FFmpeg "-y -i `"$Path`" -c:v libx264 -crf 18 -c:a aac -b:a 192k `"$outFile`""
    Write-Success "完成: $outFile"
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
    $outFile = [System.IO.Path]::ChangeExtension($Path, "_spectrum.jpg")
    Write-Info "[生成频谱]"
    Invoke-FFmpeg "-y -i `"$Path`" -lavfi `"showspectrumpic=s=1920x1080:color=magma:scale=log:legend=1`" -frames:v 1 -update 1 `"$outFile`""
    Write-Success "完成: $outFile"
}

function Compare-SSIM {
    param([string]$f1, [string]$f2)
    if (-not (Test-Path -LiteralPath $f1) -or -not (Test-Path -LiteralPath $f2)) { Write-Warn "请确保两个文件都已选择"; return }
    Write-Info "[SSIM 对比]"
    $output = cmd /c "$ffmpegPath -i `"$f1`" -i `"$f2`" -filter_complex ssim -f null - 2>&1"
    $line = $output | Where-Object { $_ -match "All:(\d\.\d+)" }
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
    Invoke-FFmpeg "-y -i `"$f1`" -i `"$f2`" -filter_complex `"blend=all_mode=difference,lutyuv=y=val*10:u=val:v=val`" -frames:v 1 -q:v 2 -update 1 `"$outFile`""
    Write-Success "已保存: $outFile"
}

function Compare-Quality {
    param([string]$f1, [string]$f2)
    if (-not (Test-Path -LiteralPath $f1) -or -not (Test-Path -LiteralPath $f2)) { Write-Warn "请确保两个文件都已选择"; return }
    Write-Info "[全方位质量对比]"
    Write-Info "1/2 计算 SSIM..."
    $output = cmd /c "$ffmpegPath -i `"$f1`" -i `"$f2`" -filter_complex ssim -f null - 2>&1"
    $scoreText = "失败"
    if (($output | Where-Object { $_ -match "All:(\d\.\d+)" }) -match "All:(\d\.\d+)") {
        $val = [double]::Parse($matches[1], [System.Globalization.CultureInfo]::InvariantCulture)
        $scoreText = "$( ($val * 100).ToString('F4') ) %"
    }
    $outFile = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($f1), "quality_report.jpg")
    Write-Info "2/2 生成差值图..."
    Invoke-FFmpeg "-y -i `"$f1`" -i `"$f2`" -filter_complex `"blend=all_mode=difference,lutyuv=y=val*10:u=val:v=val`" -frames:v 1 -q:v 2 -update 1 `"$outFile`""
    Write-Success "结果: SSIM $scoreText"
    Write-Success "图片: $outFile"
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
    $tmpDir = [System.IO.Path]::Combine($env:TEMP, "ffmpeg_toolbox_sub")
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    
    $ext = [System.IO.Path]::GetExtension($subFile).ToLower()
    $localSub = [System.IO.Path]::Combine($tmpDir, "subtitle$ext")
    Copy-Item -LiteralPath $subFile -Destination $localSub -Force
    
    if ($ext -eq ".srt") {
        Write-Info "SRT -> ASS 转换..."
        Push-Location $tmpDir
        cmd /c "$ffmpegPath -sub_charenc UTF-8 -i subtitle.srt subtitle.ass 2>&1"
        Pop-Location
        $assLocal = [System.IO.Path]::Combine($tmpDir, "subtitle.ass")
        if (Test-Path -LiteralPath $assLocal) {
            $assContent = Get-Content -LiteralPath $assLocal -Raw -Encoding UTF8
            $assContent = $assContent -replace '(?<=Style: Default,)[^,]+', $fontName
            Set-Content -LiteralPath $assLocal -Value $assContent -Encoding UTF8
            $localSub = $assLocal
        }
    } elseif ($ext -eq ".ass") {
        $assContent = Get-Content -LiteralPath $localSub -Raw -Encoding UTF8
        $assContent = $assContent -replace '(?<=Style: Default,)[^,]+', $fontName
        Set-Content -LiteralPath $localSub -Value $assContent -Encoding UTF8
    }
    
    $outFile = [System.IO.Path]::Combine(
        [System.IO.Path]::GetDirectoryName($VideoPath),
        [System.IO.Path]::GetFileNameWithoutExtension($VideoPath) + "_sub.mp4"
    )
    
    Write-Info "压制字幕 (CRF18, audio copy)..."
    Push-Location $tmpDir
    $subName = [System.IO.Path]::GetFileName($localSub)
    cmd /c "$ffmpegPath -y -i `"$VideoPath`" -vf `"subtitles=$subName`" -c:v libx264 -crf 18 -preset slow -c:a copy `"$outFile`" 2>&1"
    Pop-Location
    
    Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Success "完成: $outFile"
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
$DWMWA_CAPTION_COLOR = if ([Environment]::OSVersion.Version.Build -ge 22000) { 20 } else { 19 }

$form = New-Object System.Windows.Forms.Form
$form.Text = "ffmpeg 自动工具箱"
$form.Size = New-Object System.Drawing.Size(760, 620)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = $C_BG
$form.ForeColor = $C_FG
$form.Font = New-Object System.Drawing.Font($FONT_UI, 9)
$form.AllowDrop = $true
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false

# ---- 拖拽区 ----
$pnlDrop = New-Object System.Windows.Forms.Panel
$pnlDrop.Size = New-Object System.Drawing.Size(720, 60)
$pnlDrop.Location = New-Object System.Drawing.Point(15, 12)
$pnlDrop.BackColor = $C_BG2
$pnlDrop.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$pnlDrop.AllowDrop = $true

$lblDropHint = New-Object System.Windows.Forms.Label
$lblDropHint.Text = "拖拽视频文件到此处"
$lblDropHint.AutoSize = $false
$lblDropHint.Dock = [System.Windows.Forms.DockStyle]::Fill
$lblDropHint.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblDropHint.ForeColor = $C_BRD
$lblDropHint.Font = New-Object System.Drawing.Font($FONT_UI, 10)
$pnlDrop.Controls.Add($lblDropHint)

$form.Controls.Add($pnlDrop)

# 文件信息标签
$lblFile = New-Object System.Windows.Forms.Label
$lblFile.Location = New-Object System.Drawing.Point(15, 78)
$lblFile.Size = New-Object System.Drawing.Size(720, 36)
$lblFile.ForeColor = $C_BRD
$lblFile.Font = New-Object System.Drawing.Font($FONT_UI, 9)
$lblFile.Text = "文件: 未选择"
$form.Controls.Add($lblFile)

# 拖拽事件
function Invoke-Drop {
    $files = $_.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
    if ($files.Count -gt 0) {
        $Script:CurrentFile = $files[0]
        $info = Get-VideoInfo $Script:CurrentFile
        if ($info) {
            $lblFile.Text = "文件: $(Split-Path $Script:CurrentFile -Leaf)  |  $info"
            $lblFile.ForeColor = $C_OK
        } else {
            Update-FileLabel
        }
        if ($files.Count -gt 1) {
            $Script:SecondFile = $files[1]
            Update-FileLabel
        }
    }
}

$pnlDrop.Add_DragEnter({ $_.Effect = [System.Windows.Forms.DragDropEffects]::Copy })
$pnlDrop.Add_DragDrop({ Invoke-Drop })
$form.Add_DragEnter({ $_.Effect = [System.Windows.Forms.DragDropEffects]::Copy })
$form.Add_DragDrop({ Invoke-Drop })

# ---- 功能按钮 ----
function New-Btn {
    param([string]$Text, [int]$X, [int]$Y, [scriptblock]$Action, [int]$W = 170, [int]$H = 34)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Object System.Drawing.Point($X, $Y)
    $btn.Size = New-Object System.Drawing.Size($W, $H)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.BackColor = $C_BG3
    $btn.ForeColor = $C_FG
    $btn.Font = New-Object System.Drawing.Font($FONT_UI, 9)
    $btn.FlatAppearance.BorderColor = $C_BRD
    $btn.FlatAppearance.MouseOverBackColor = $C_ACCH
    $btn.FlatAppearance.MouseDownBackColor = $C_ACC
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.Add_Click($Action)
    $form.Controls.Add($btn)
}

$btnY = 120

New-Btn "1. 格式转换 (低损耗)"     16    $btnY         { Clear-Console; Convert-LowLoss    $Script:CurrentFile }
New-Btn "2. 格式转换 (普通)"       202   $btnY         { Clear-Console; Convert-Normal     $Script:CurrentFile }
New-Btn "3. 核对参数"              388   $btnY         { Clear-Console; Test-Probe         $Script:CurrentFile }
New-Btn "4. 生成频谱"              574   $btnY         { Clear-Console; New-Spectrum       $Script:CurrentFile }

$btnY += 42
New-Btn "5. SSIM 对比"              16    $btnY         { Clear-Console; $s = if (-not $Script:SecondFile) { Show-FileDialog "选择对比文件" "视频|*.mp4;*.webm;*.mkv;*.avi|所有|*.*" }; if ($s) { $Script:SecondFile = $s; Update-FileLabel }; Compare-SSIM $Script:CurrentFile $Script:SecondFile }
New-Btn "6. 差值图"                202   $btnY         { Clear-Console; $s = if (-not $Script:SecondFile) { Show-FileDialog "选择对比文件" "视频|*.mp4;*.webm;*.mkv;*.avi|所有|*.*" }; if ($s) { $Script:SecondFile = $s; Update-FileLabel }; Compare-Diff $Script:CurrentFile $Script:SecondFile }
New-Btn "7. 质量对比 (分值+图)"    388   $btnY         { Clear-Console; $s = if (-not $Script:SecondFile) { Show-FileDialog "选择对比文件" "视频|*.mp4;*.webm;*.mkv;*.avi|所有|*.*" }; if ($s) { $Script:SecondFile = $s; Update-FileLabel }; Compare-Quality $Script:CurrentFile $Script:SecondFile }
New-Btn "8. 嵌入硬字幕"            574   $btnY         { Clear-Console; Convert-Subtitle   $Script:CurrentFile }

$btnY += 42

$btnClearSecond = New-Object System.Windows.Forms.Button
$btnClearSecond.Text = "清除对比文件"
$btnClearSecond.Location = New-Object System.Drawing.Point(15, $btnY)
$btnClearSecond.Size = New-Object System.Drawing.Size(170, 26)
$btnClearSecond.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClearSecond.BackColor = $C_BG3
$btnClearSecond.ForeColor = $C_FG
$btnClearSecond.FlatAppearance.BorderColor = $C_BRD
$btnClearSecond.Font = New-Object System.Drawing.Font($FONT_UI, 8)
$btnClearSecond.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnClearSecond.Add_Click({
    $Script:SecondFile = ""
    Update-FileLabel
    Write-Info "对比文件已清除"
})
$form.Controls.Add($btnClearSecond)

# ---- 控制台输出 ----
$rtbY = $btnY + 40
$rtb = New-Object System.Windows.Forms.RichTextBox
$rtb.Location = New-Object System.Drawing.Point(15, $rtbY)
$rtb.Size = New-Object System.Drawing.Size(720, 200)
$rtb.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
$rtb.ForeColor = $C_CON
$rtb.Font = New-Object System.Drawing.Font($FONT_MONO, 9)
$rtb.ReadOnly = $true
$rtb.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtb.WordWrap = $false
$form.Controls.Add($rtb)

# ---- 底部状态栏 ----
$pnlStatus = New-Object System.Windows.Forms.Panel
$pnlStatus.Size = New-Object System.Drawing.Size(760, 22)
$pnlStatus.Location = New-Object System.Drawing.Point(0, ([int]$form.ClientSize.Height - 22))
$pnlStatus.BackColor = $C_BG2
$pnlStatus.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "  准备就绪"
$lblStatus.AutoSize = $true
$lblStatus.Location = New-Object System.Drawing.Point(4, 3)
$lblStatus.ForeColor = $C_FG
$lblStatus.Font = New-Object System.Drawing.Font($FONT_UI, 8)
$pnlStatus.Controls.Add($lblStatus)
$form.Controls.Add($pnlStatus)

# ============================================================
# 7. 入口
# ============================================================
if ($File1 -and (Test-Path -LiteralPath $File1)) {
    $Script:CurrentFile = $File1
    if ($File2 -and (Test-Path -LiteralPath $File2)) { $Script:SecondFile = $File2 }
}

[System.Windows.Forms.Application]::EnableVisualStyles()
Update-FileLabel
Write-Info "ffmpeg 自动工具箱 GUI 已就绪"

# 标题栏暗色 (Shown 事件触发)
$form.Add_Shown({
    $darkVal = 1
    [DwmApi]::DwmSetWindowAttribute($form.Handle, $DWMWA_CAPTION_COLOR, [ref]$darkVal, 4)
})

$form.ShowDialog() | Out-Null
