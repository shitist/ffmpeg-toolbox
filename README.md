# ffmpeg-toolbox

> 一个基于 ffmpeg 的交互式视频处理工具箱，支持格式转换、质量对比、参数查看、频谱图、硬字幕等功能。
> An interactive ffmpeg-based video processing toolbox with format conversion, quality comparison, parameter inspection, spectrum images, hard subtitles and more.

![version](https://img.shields.io/badge/version-v2.1.0-blue) [![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## 功能 / Features

| # | 中文 | English |
|---|------|---------|
| 1 | **格式转换: webm 转 mp4（低损耗）** | Convert webm to mp4 (low-loss, CRF18, slow preset, 320k audio) |
| 2 | **格式转换: webm 转 mp4（普通）** | Convert webm to mp4 (normal, CRF18, 192k audio) |
| 3 | **核对分辨率、码率等基础参数** | Inspect video resolution, bitrate, frame rate via ffprobe |
| 4 | **分色带刻度频谱** | Generate color spectrum visualization (showspectrumpic) |
| 5 | **SSIM 还原百分比（双文件对比）** | SSIM structural similarity comparison between two files |
| 6 | **差值图（高亮强化，双文件对比）** | Generate difference map with enhanced highlights |
| 7 | **全方位质量对比（分值+图）** | Comprehensive quality comparison (SSIM score + difference image) |
| 8 | **嵌入硬字幕（高画质）** | Burn hard subtitles (GUI: CRF 16, compatible YUV420P; CLI: CRF 18) |

---

## 使用方法 / Usage

### Windows GUI

双击运行 `ffmpeg_toolbox_gui.exe`，拖入视频文件后点击功能按钮即可。
Double-click `ffmpeg_toolbox_gui.exe`, drag in a video file, then click an action button.

- 拖拽视频到窗口自动显示分辨率/帧率/码率
- 功能按钮一键运行，内嵌控制台实时输出
- 实时进度条（百分比 + 耗时 + 剩余时间 + 编码速度）
- 支持中途取消任务，崩溃自动恢复并报错
- 对比和字幕功能自动弹出文件选择框
- 支持 Noto Sans 中文、Noto Sans 日文和微软雅黑，默认使用 Noto Sans 中文
- 压制前可预览所选字体在视频中的实际字幕效果
- 支持 SRT、ASS 字幕，保留 ASS 原有的字号、粗细和位置设置

内置 Noto 字体，无需另行安装。字体遵循 [SIL OFL 1.1](assets/fonts/OFL.txt)，详见 [字体说明](assets/fonts/FONT-NOTICE.txt)。

从源码运行 Windows GUI 时需保留 `assets/fonts`。已安装 `ps2exe` 的 Windows PowerShell 中可运行 `powershell -NoProfile -ExecutionPolicy Bypass -File .\build_gui.ps1`，重建包含字体的 EXE。

### macOS GUI

macOS GUI 位于 `ffmpeg_toolbox_gui_mac/`，是一套独立的 Electron 应用工程，已包含 GUI 和 ffmpeg/ffprobe 调用逻辑。
The macOS GUI lives in `ffmpeg_toolbox_gui_mac/`. It is a standalone Electron app containing both the GUI and ffmpeg/ffprobe task logic.

macOS 版支持内置 Noto Sans 中日文字体选择，并可在压制前预览真实视频画面中的字幕效果。

源码运行 / Run from source:

```sh
cd ffmpeg_toolbox_gui_mac
npm install
npm start
```

打包 macOS 应用 / Build a macOS app:

```sh
npm run build:mac
```

公开分发 `.app` / `.dmg` 时，建议进行 Apple 代码签名和 notarization。
For public `.app` / `.dmg` distribution, Apple code signing and notarization are recommended.

### 交互菜单 / Interactive Menu
双击运行 `ffmpeg自动工具箱.exe` 或 `ffmpeg自动工具箱.bat`，在菜单中选择功能编号即可。  
Double-click `ffmpeg自动工具箱.exe` or `ffmpeg自动工具箱.bat`, then select a function by number.

### 拖拽文件 / Drag and Drop
将视频文件直接拖到 exe 或 bat 图标上，工具会自动识别文件路径，跳过输入步骤。  
Drag video files onto the exe/bat icon to auto-detect file paths and skip manual input.

也可以同时拖入两个文件用于对比功能（SSIM、差值图、质量对比），或视频+字幕用于硬字幕嵌入。  
You can also drag two files at once for comparison (SSIM, diff, quality) or video+subtitle for hard subtitles.

---

## 依赖 / Requirements

- **ffmpeg** (含 ffprobe) — 下载: [ffmpeg.org](https://ffmpeg.org/download.html)
- **Windows GUI / CLI**: Windows, PowerShell 5.1+
- **macOS GUI**: macOS, Node.js, npm；字幕功能需要带 libass/subtitles 滤镜的 ffmpeg

启动时，工具会检测 ffmpeg。Windows CLI 可在未找到时手动输入路径；macOS GUI 会检测 PATH，并优先识别 Homebrew 的 `ffmpeg-full`。
On launch, the tool detects ffmpeg. Windows CLI can prompt for a manual path; the macOS GUI checks PATH and also prefers Homebrew's `ffmpeg-full`.

---

## 安装 / Installation

### Windows

1. 从 [Releases](https://github.com/shitist/ffmpeg-toolbox/releases) 下载最新版本，或者直接克隆仓库。  
   Download the latest release from [Releases](https://github.com/shitist/ffmpeg-toolbox/releases), or clone the repository directly.
2. 确保 ffmpeg 已安装并配置到系统 PATH 中。  
   Make sure ffmpeg is installed and added to your system PATH.
3. 运行 `ffmpeg_toolbox_gui.exe` 或 `ffmpeg自动工具箱.exe`。
   Run `ffmpeg_toolbox_gui.exe` or `ffmpeg自动工具箱.exe`.

### macOS

1. 安装包含 libass 字幕滤镜的 ffmpeg-full。
   Install ffmpeg-full with the libass subtitle filter.

   ```sh
   brew install ffmpeg-full
   ```

2. 安装并启动 Mac GUI。
   Install and start the Mac GUI.

   ```sh
   cd ffmpeg_toolbox_gui_mac
   npm install
   npm start
   ```

---

## 项目结构 / Project Structure

```
ffmpeg-toolbox/
├── ffmpeg_toolbox.ps1          # 主脚本 (PowerShell CLI) / Main script (CLI)
├── ffmpeg_toolbox_gui.ps1      # GUI 脚本 (PowerShell) / GUI script
├── build_gui.ps1               # GUI 打包脚本（含内置字体）/ GUI build script
├── assets/fonts/               # Noto 静态字体及 OFL 许可 / Bundled static fonts and license
├── ffmpeg_toolbox_gui_mac/     # macOS GUI (Electron)
│   ├── package.json            # npm scripts and Electron config
│   ├── package-lock.json       # locked npm dependencies
│   ├── README.md               # macOS GUI notes
│   └── src/                    # Electron main/preload/renderer source
├── ffmpeg自动工具箱.bat         # 批处理启动器 / Batch launcher
├── ffmpeg自动工具箱.exe         # CLI 打包可执行文件 / Packaged CLI executable
├── ffmpeg_toolbox_gui.exe      # GUI 打包可执行文件 / Packaged GUI executable
├── README.md                   # 说明文件 / This file
└── LICENSE                     # MIT License
```
