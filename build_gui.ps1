param([string]$OutputFile = (Join-Path $PSScriptRoot 'ffmpeg_toolbox_gui.exe'))

$ErrorActionPreference = 'Stop'
Import-Module ps2exe -ErrorAction Stop
$fontDirectory = Join-Path $PSScriptRoot 'assets\fonts'
$embedded = @{}
foreach ($name in @('NotoSansCJK-Regular.ttc', 'NotoSansCJK-Bold.ttc', 'OFL.txt', 'FONT-NOTICE.txt')) {
    $isFont = $name.EndsWith('.ttc')
    $sourceName = if ($isFont) { 'noto-cjk\' + $name } else { $name }
    $targetName = if ($isFont) { 'fonts\' + $name } else { $name }
    $path = Join-Path $fontDirectory $sourceName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing font resource: $path" }
    $embedded['%LOCALAPPDATA%\ffmpeg-toolbox\fonts\noto-cjk-2.004\' + $targetName] = $path
}

Invoke-ps2exe -inputFile (Join-Path $PSScriptRoot 'ffmpeg_toolbox_gui.ps1') -outputFile $OutputFile -noConsole -STA -embedFiles $embedded
