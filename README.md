# ffmpeg-toolbox

> 一个基于 ffmpeg 的交互式视频处理工具箱，支持格式转换、质量对比、参数查看等功能。
> An interactive ffmpeg-based video processing toolbox with format conversion, quality comparison, parameter inspection and more.

---

## 功能 / Features

| # | 中文 | English |
|---|------|---------|
| 1 | **格式转换: webm 转 mp4（低损耗）** | Convert webm to mp4 (low-loss, CRF 18, slow preset, 320k audio) |
| 2 | **格式转换: webm 转 mp4（普通）** | Convert webm to mp4 (normal, CRF 18, 192k audio) |
| 3 | **核对分辨率、码率等基础参数** | Inspect video resolution, bitrate, frame rate via ffprobe |
| 4 | **分色带刻度频谱** | Generate color spectrum visualization (showspectrumpic) |
| 5 | **SSIM 还原百分比（双文件对比）** | SSIM structural similarity comparison between two files |
| 6 | **差值图（高亮强化，双文件对比）** | Generate difference map with enhanced highlights |
| 7 | **全方位质量对比（分值+图）** | Comprehensive quality comparison (SSIM score + difference image) |

---

## 使用方法 / Usage

### 交互菜单 / Interactive Menu
双击运行 `ffmpeg自动工具箱.exe` 或 `ffmpeg自动工具箱.bat`，在菜单中选择功能编号即可。  
Double-click `ffmpeg自动工具箱.exe` or `ffmpeg自动工具箱.bat`, then select a function by number.

### 拖拽文件 / Drag and Drop
将视频文件直接拖到 exe 或 bat 图标上，工具会自动识别文件路径，跳过输入步骤。  
Drag video files onto the exe/bat icon to auto-detect file paths and skip manual input.

也可以同时拖入两个文件用于对比功能（SSIM、差值图、质量对比）。  
You can also drag two files at once for comparison features (SSIM, diff, quality report).

---

## 依赖 / Requirements

- **ffmpeg** (含 ffprobe) — 下载: [ffmpeg.org](https://ffmpeg.org/download.html)
- **Windows** (PowerShell 5.1+)

首次启动时，工具会自动检测系统 PATH 中的 ffmpeg。如果未找到，会提示手动输入路径。  
On first launch, the tool auto-detects ffmpeg from your system PATH. If not found, you will be prompted to enter the path manually.

---

## 安装 / Installation

1. 从 [Releases](https://github.com/shitist/ffmpeg-toolbox/releases) 下载最新版本，或者直接克隆仓库。  
   Download the latest release from [Releases](https://github.com/shitist/ffmpeg-toolbox/releases), or clone the repository directly.
2. 确保 ffmpeg 已安装并配置到系统 PATH 中。  
   Make sure ffmpeg is installed and added to your system PATH.
3. 运行 `ffmpeg自动工具箱.exe` 即可。  
   Run `ffmpeg自动工具箱.exe` to start.

---

## 项目结构 / Project Structure

```
ffmpeg-toolbox/
├── ffmpeg_toolbox.ps1          # 主脚本 (PowerShell) / Main script
├── ffmpeg自动工具箱.bat        # 批处理启动器 / Batch launcher
├── ffmpeg自动工具箱.exe        # 打包的可执行文件 (PS2EXE) / Packaged executable
├── ffmpeg代码集.txt            # ffmpeg 参考命令笔记 / ffmpeg command reference
└── README.md                   # 说明文件 / This file
```

---

## License

MIT
