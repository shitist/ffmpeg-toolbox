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

## Requirements

- macOS
- Node.js and npm
- ffmpeg and ffprobe available in `PATH`

Install ffmpeg with Homebrew if needed:

```sh
brew install ffmpeg
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
