# ffmpeg_toolbox_gui_mac

Mac-focused Electron GUI for `ffmpeg-toolbox`.

This app is intentionally separate from the existing PowerShell GUI. It contains its own GUI and ffmpeg/ffprobe task logic, so it does not call the Windows `.ps1` scripts at runtime.

Implemented tasks:

- Convert to MP4, low-loss and normal presets
- Inspect video parameters with ffprobe
- Generate spectrum images
- Compare SSIM
- Generate difference images
- Generate quality reports
- Burn hard subtitles from SRT/ASS
- Choose bundled Noto Sans Chinese or Japanese subtitle fonts
- Preview the selected font on a real video frame before encoding

The app includes Noto Sans CJK 2.004 Regular and Bold. The bundled fonts are
loaded only by ffmpeg and are not installed as macOS system fonts. See
`assets/fonts/FONT-NOTICE.txt` and `assets/fonts/OFL.txt` for attribution and
license details.

## Requirements

- macOS
- Node.js and npm
- ffmpeg and ffprobe
- The ffmpeg `subtitles` filter (libass) for subtitle preview and hard subtitles

Homebrew's regular `ffmpeg` formula may omit libass. Install `ffmpeg-full` for
all features; the app automatically detects its keg-only path:

```sh
brew install ffmpeg-full
```

## Development

```sh
cd ffmpeg_toolbox_gui_mac
npm install
npm start
```

## Build

```sh
npm run build:mac
```

For public distribution outside your own Mac, sign and notarize the generated macOS app with an Apple Developer certificate.
