const { app, BrowserWindow, dialog, ipcMain, shell } = require("electron");
const { spawn, spawnSync } = require("node:child_process");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");
const {
  applySubtitleFont,
  buildSubtitleFilter,
  getSubtitleFontPreset,
  getSubtitlePreviewTime,
  listSubtitleFonts
} = require("./subtitles");

let mainWindow;
let activeTask = null;
const subtitleFilterCache = new Map();

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1040,
    height: 720,
    minWidth: 920,
    minHeight: 640,
    title: "ffmpeg 自动工具箱",
    backgroundColor: "#141518",
    titleBarStyle: process.platform === "darwin" ? "hiddenInset" : "default",
    webPreferences: {
      preload: path.join(__dirname, "../preload/preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false
    }
  });

  mainWindow.loadFile(path.join(__dirname, "../renderer/index.html"));
}

app.whenReady().then(() => {
  createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});

function findBinary(name) {
  const resourceCandidate = path.join(process.resourcesPath || "", "bin", name);
  if (resourceCandidate && spawnSync("test", ["-x", resourceCandidate]).status === 0) {
    return resourceCandidate;
  }

  const fullCandidates = [
    path.join("/opt/homebrew/opt/ffmpeg-full/bin", name),
    path.join("/usr/local/opt/ffmpeg-full/bin", name)
  ];
  for (const candidate of fullCandidates) {
    if (spawnSync("test", ["-x", candidate]).status === 0) return candidate;
  }

  const result = spawnSync("which", [name], { encoding: "utf8" });
  if (result.status === 0) return result.stdout.trim();
  return "";
}

function getToolPaths() {
  return {
    ffmpeg: findBinary("ffmpeg"),
    ffprobe: findBinary("ffprobe")
  };
}

ipcMain.handle("toolbox:get-status", () => {
  const paths = getToolPaths();
  return {
    ok: Boolean(paths.ffmpeg && paths.ffprobe),
    paths,
    subtitleSupported: Boolean(paths.ffmpeg && hasSubtitleFilter(paths.ffmpeg))
  };
});

ipcMain.handle("toolbox:select-video-files", async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    title: "选择视频文件",
    properties: ["openFile", "multiSelections"],
    filters: [
      { name: "Video", extensions: ["mp4", "webm", "mkv", "avi", "mov", "m4v"] },
      { name: "All Files", extensions: ["*"] }
    ]
  });
  return result.canceled ? [] : result.filePaths;
});

ipcMain.handle("toolbox:select-subtitle-file", async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    title: "选择字幕文件",
    properties: ["openFile"],
    filters: [
      { name: "Subtitle", extensions: ["srt", "ass"] },
      { name: "All Files", extensions: ["*"] }
    ]
  });
  return result.canceled ? "" : result.filePaths[0];
});

ipcMain.handle("toolbox:get-subtitle-fonts", async () => {
  try {
    await assertSubtitleFonts();
    return { ok: true, fonts: listSubtitleFonts() };
  } catch (error) {
    return { ok: false, message: error.message || String(error), fonts: [] };
  }
});

ipcMain.handle("toolbox:preview-subtitle", async (_event, request) => {
  if (activeTask) return { ok: false, message: "请等待当前任务结束后再预览字幕" };

  const paths = getToolPaths();
  if (!paths.ffmpeg || !paths.ffprobe) {
    return { ok: false, message: "未找到 ffmpeg / ffprobe，请先安装并加入 PATH" };
  }
  if (!hasSubtitleFilter(paths.ffmpeg)) {
    return { ok: false, message: getSubtitleDependencyMessage() };
  }

  try {
    const preview = await createSubtitlePreview(request || {}, paths);
    return { ok: true, ...preview };
  } catch (error) {
    return { ok: false, message: error.message || String(error) };
  }
});

ipcMain.handle("toolbox:reveal-path", async (_event, filePath) => {
  if (filePath) shell.showItemInFolder(filePath);
});

ipcMain.handle("toolbox:cancel-task", () => {
  if (!activeTask) return { ok: false, message: "没有正在运行的任务" };
  activeTask.cancelled = true;
  if (activeTask.process && !activeTask.process.killed) activeTask.process.kill("SIGTERM");
  emitTask({ type: "log", level: "warn", message: "[!] 用户取消了任务，正在终止进程..." });
  return { ok: true };
});

ipcMain.handle("toolbox:start-task", async (_event, request) => {
  if (activeTask) return { ok: false, message: "已有任务正在运行" };

  const paths = getToolPaths();
  if (!paths.ffmpeg || !paths.ffprobe) {
    return { ok: false, message: "未找到 ffmpeg / ffprobe，请先安装并加入 PATH" };
  }
  if (request.action === "subtitle" && !hasSubtitleFilter(paths.ffmpeg)) {
    return { ok: false, message: getSubtitleDependencyMessage() };
  }

  const taskId = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  activeTask = { id: taskId, process: null, cancelled: false, tempDirs: [] };

  runTask(taskId, request, paths)
    .catch((error) => {
      emitTask({ type: "log", level: "error", message: error.message || String(error) });
      emitTask({ type: "done", ok: false });
    })
    .finally(async () => {
      const tempDirs = activeTask && activeTask.id === taskId ? activeTask.tempDirs : [];
      activeTask = null;
      for (const dir of tempDirs) {
        await fs.rm(dir, { recursive: true, force: true }).catch(() => {});
      }
    });

  return { ok: true, taskId };
});

function emitTask(payload) {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send("toolbox:task-event", payload);
  }
}

async function runTask(taskId, request, paths) {
  const task = activeTask;
  const primary = request.primaryFile || "";
  const secondary = request.secondaryFile || "";

  emitTask({ type: "started", taskId, action: request.action });

  switch (request.action) {
    case "probe":
      await inspectVideo(primary, paths);
      break;
    case "convertLowLoss":
      await convertVideo(primary, paths, "lowloss", ["-c:v", "libx264", "-crf", "18", "-preset", "slow", "-c:a", "aac", "-b:a", "320k"]);
      break;
    case "convertNormal":
      await convertVideo(primary, paths, "normal", ["-c:v", "libx264", "-crf", "18", "-c:a", "aac", "-b:a", "192k"]);
      break;
    case "spectrum":
      await createSpectrum(primary, paths);
      break;
    case "ssim":
      await compareSsim(primary, secondary, paths);
      break;
    case "diff":
      await createDiff(primary, secondary, paths, "difference.jpg");
      break;
    case "quality":
      await createQualityReport(primary, secondary, paths);
      break;
    case "subtitle":
      await burnSubtitle(primary, request.subtitleFile, request.fontId, paths, task);
      break;
    default:
      throw new Error("未知任务");
  }
}

async function assertFile(filePath, label) {
  if (!filePath) throw new Error(`${label} 未选择`);
  const stat = await fs.stat(filePath).catch(() => null);
  if (!stat || !stat.isFile()) throw new Error(`${label} 不存在`);
}

function siblingOutput(input, suffix, ext) {
  const parsed = path.parse(input);
  return path.join(parsed.dir, `${parsed.name}_${suffix}${ext}`);
}

async function getVideoDuration(filePath, paths) {
  await assertFile(filePath, "视频文件");
  const args = ["-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", filePath];
  const result = await runProcess(paths.ffprobe, args, { collect: true });
  const value = Number.parseFloat(result.output.trim());
  return Number.isFinite(value) ? value : 0;
}

async function getVideoInfo(filePath, paths) {
  await assertFile(filePath, "视频文件");
  const args = ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=bit_rate,width,height,r_frame_rate", "-of", "default=noprint_wrappers=1", filePath];
  const result = await runProcess(paths.ffprobe, args, { collect: true });
  return result.output.trim();
}

async function inspectVideo(filePath, paths) {
  emitTask({ type: "log", level: "info", message: "[核对参数]" });
  const output = await getVideoInfo(filePath, paths);
  for (const line of output.split(/\r?\n/).filter(Boolean)) {
    emitTask({ type: "log", level: "plain", message: line });
  }
  emitTask({ type: "done", ok: true });
}

async function convertVideo(filePath, paths, suffix, codecArgs) {
  await assertFile(filePath, "视频文件");
  const output = siblingOutput(filePath, suffix, ".mp4");
  const label = suffix === "lowloss" ? "[格式转换: 低损耗]" : "[格式转换: 普通]";
  emitTask({ type: "log", level: "info", message: label });
  const duration = await getVideoDuration(filePath, paths);
  await runFfmpeg(paths, ["-y", "-i", filePath, ...codecArgs, output], duration);
  emitTask({ type: "done", ok: true, outputPath: output, message: `完成: ${output}` });
}

async function createSpectrum(filePath, paths) {
  await assertFile(filePath, "视频文件");
  const output = siblingOutput(filePath, "spectrum", ".jpg");
  emitTask({ type: "log", level: "info", message: "[生成频谱]" });
  await runFfmpeg(paths, [
    "-y",
    "-i",
    filePath,
    "-lavfi",
    "showspectrumpic=s=1920x1080:color=magma:scale=log:legend=1",
    "-frames:v",
    "1",
    "-update",
    "1",
    output
  ]);
  emitTask({ type: "done", ok: true, outputPath: output, message: `完成: ${output}` });
}

async function compareSsim(first, second, paths) {
  await assertFile(first, "第一个视频文件");
  await assertFile(second, "对比视频文件");
  emitTask({ type: "log", level: "info", message: "[SSIM 对比]" });
  const duration = await getVideoDuration(first, paths);
  const result = await runFfmpeg(paths, ["-y", "-i", first, "-i", second, "-filter_complex", "ssim", "-f", "null", "-"], duration);
  const score = parseSsim(result.output);
  if (!score) {
    emitTask({ type: "log", level: "warn", message: "无法解析分值" });
    emitTask({ type: "done", ok: false });
    return;
  }
  emitTask({ type: "done", ok: true, message: `还原度: ${(score * 100).toFixed(4)} %` });
}

async function createDiff(first, second, paths, outputName) {
  await assertFile(first, "第一个视频文件");
  await assertFile(second, "对比视频文件");
  const output = path.join(path.dirname(first), outputName);
  emitTask({ type: "log", level: "info", message: "[生成差值图]" });
  await runFfmpeg(paths, [
    "-y",
    "-i",
    first,
    "-i",
    second,
    "-filter_complex",
    "blend=all_mode=difference,lutyuv=y=val*10:u=val:v=val",
    "-frames:v",
    "1",
    "-q:v",
    "2",
    "-update",
    "1",
    output
  ]);
  emitTask({ type: "done", ok: true, outputPath: output, message: `已保存: ${output}` });
}

async function createQualityReport(first, second, paths) {
  await assertFile(first, "第一个视频文件");
  await assertFile(second, "对比视频文件");
  emitTask({ type: "log", level: "info", message: "[全方位质量对比]" });
  emitTask({ type: "log", level: "info", message: "1/2 计算 SSIM..." });
  const duration = await getVideoDuration(first, paths);
  const ssimResult = await runFfmpeg(paths, ["-y", "-i", first, "-i", second, "-filter_complex", "ssim", "-f", "null", "-"], duration);
  const score = parseSsim(ssimResult.output);
  const scoreText = score ? `${(score * 100).toFixed(4)} %` : "失败";

  emitTask({ type: "log", level: "info", message: "2/2 生成差值图..." });
  const output = path.join(path.dirname(first), "quality_report.jpg");
  await runFfmpeg(paths, [
    "-y",
    "-i",
    first,
    "-i",
    second,
    "-filter_complex",
    "blend=all_mode=difference,lutyuv=y=val*10:u=val:v=val",
    "-frames:v",
    "1",
    "-q:v",
    "2",
    "-update",
    "1",
    output
  ]);
  emitTask({ type: "done", ok: true, outputPath: output, message: `结果: SSIM ${scoreText}\n图片: ${output}` });
}

async function burnSubtitle(videoPath, subtitlePath, fontId, paths, task) {
  await assertFile(videoPath, "视频文件");
  await assertFile(subtitlePath, "字幕文件");
  emitTask({ type: "log", level: "info", message: "[嵌入硬字幕]" });

  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "ffmpeg_toolbox_sub_"));
  task.tempDirs.push(tempDir);
  const subtitleExt = path.extname(subtitlePath).toLowerCase();
  if (subtitleExt === ".srt") {
    emitTask({ type: "log", level: "info", message: "SRT -> ASS 转换..." });
  }

  const prepared = await prepareSubtitle(subtitlePath, fontId, paths, tempDir);
  emitTask({ type: "log", level: "info", message: `字幕字体: ${prepared.preset.displayName}` });

  const videoExt = path.extname(videoPath).toLowerCase();
  const outputExt = videoExt === ".mp4" || videoExt === ".m4v" ? ".mp4" : videoExt === ".mov" ? ".mov" : ".mkv";
  const output = siblingOutput(videoPath, "sub", outputExt);
  const duration = await getVideoDuration(videoPath, paths);
  const subtitleFilter = buildSubtitleFilter(prepared.subtitlePath, prepared.fontDirectory);

  emitTask({ type: "log", level: "info", message: "压制字幕 (CRF 16 高质量，兼容像素格式，全部音轨原样复制)..." });
  await runFfmpeg(paths, [
    "-y",
    "-i",
    videoPath,
    "-map",
    "0:v:0",
    "-map",
    "0:a?",
    "-map_metadata",
    "0",
    "-map_chapters",
    "0",
    "-vf",
    subtitleFilter,
    "-c:v",
    "libx264",
    "-crf",
    "16",
    "-preset",
    "slow",
    "-pix_fmt",
    "yuv420p",
    "-c:a",
    "copy",
    output
  ], duration);

  emitTask({ type: "done", ok: true, outputPath: output, message: `完成: ${output}` });
}

async function createSubtitlePreview(request, paths) {
  const videoPath = typeof request.videoPath === "string" ? request.videoPath : "";
  const subtitlePath = typeof request.subtitlePath === "string" ? request.subtitlePath : "";
  await assertFile(videoPath, "视频文件");
  await assertFile(subtitlePath, "字幕文件");

  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "ffmpeg_toolbox_preview_"));
  try {
    const prepared = await prepareSubtitle(subtitlePath, request.fontId, paths, tempDir, { silent: true, trackTask: false });
    const previewTime = getSubtitlePreviewTime(prepared.content);
    if (previewTime === null) throw new Error("字幕中没有可预览的台词");

    const output = path.join(tempDir, "preview.png");
    const seconds = previewTime.toFixed(3).replace(/0+$/, "").replace(/\.$/, "");
    const subtitleFilter = buildSubtitleFilter(prepared.subtitlePath, prepared.fontDirectory);
    const videoFilter = [
      `setpts=PTS+${seconds}/TB`,
      subtitleFilter,
      "scale=960:540:force_original_aspect_ratio=decrease",
      "pad=960:540:(ow-iw)/2:(oh-ih)/2:color=0x0c0d0f"
    ].join(",");

    await runProcess(paths.ffmpeg, [
      "-nostdin",
      "-hide_banner",
      "-loglevel",
      "error",
      "-y",
      "-ss",
      seconds,
      "-i",
      videoPath,
      "-vf",
      videoFilter,
      "-frames:v",
      "1",
      "-an",
      "-sn",
      "-c:v",
      "png",
      "-threads",
      "1",
      "-update",
      "1",
      output
    ], { collect: true, silent: true, timeoutMs: 15000, trackTask: false });

    const image = await fs.readFile(output);
    return {
      fontId: prepared.preset.id,
      imageDataUrl: `data:image/png;base64,${image.toString("base64")}`,
      previewTime
    };
  } finally {
    await fs.rm(tempDir, { recursive: true, force: true }).catch(() => {});
  }
}

async function prepareSubtitle(subtitlePath, fontId, paths, tempDir, options = {}) {
  await assertFile(subtitlePath, "字幕文件");
  const fontDirectory = await assertSubtitleFonts();
  const preset = getSubtitleFontPreset(fontId);
  const subtitleExt = path.extname(subtitlePath).toLowerCase();
  if (![".srt", ".ass"].includes(subtitleExt)) throw new Error("字幕文件必须是 srt 或 ass");

  let localSubtitle = path.join(tempDir, `subtitle${subtitleExt}`);
  await fs.copyFile(subtitlePath, localSubtitle);

  if (subtitleExt === ".srt") {
    const assFile = path.join(tempDir, "subtitle.ass");
    await runProcess(paths.ffmpeg, [
      "-hide_banner",
      "-loglevel",
      "error",
      "-y",
      "-sub_charenc",
      "UTF-8",
      "-i",
      localSubtitle,
      assFile
    ], { collect: true, silent: options.silent, trackTask: options.trackTask });
    localSubtitle = assFile;
  }

  const content = applySubtitleFont(await fs.readFile(localSubtitle, "utf8"), preset, subtitleExt === ".srt");
  await fs.writeFile(localSubtitle, content, "utf8");
  return { content, fontDirectory, preset, subtitlePath: localSubtitle };
}

async function assertSubtitleFonts() {
  const fontDirectory = app.isPackaged
    ? path.join(process.resourcesPath, "fonts", "noto-cjk")
    : path.join(app.getAppPath(), "assets", "fonts", "noto-cjk");
  const required = ["NotoSansCJK-Regular.ttc", "NotoSansCJK-Bold.ttc"];
  for (const name of required) {
    const stat = await fs.stat(path.join(fontDirectory, name)).catch(() => null);
    if (!stat || !stat.isFile()) throw new Error(`内置字幕字体缺失: ${name}`);
  }
  return fontDirectory;
}

function hasSubtitleFilter(ffmpegPath) {
  if (subtitleFilterCache.has(ffmpegPath)) return subtitleFilterCache.get(ffmpegPath);
  const result = spawnSync(ffmpegPath, ["-hide_banner", "-filters"], {
    encoding: "utf8",
    maxBuffer: 8 * 1024 * 1024
  });
  const output = `${result.stdout || ""}\n${result.stderr || ""}`;
  const supported = result.status === 0 && /^\s*[TSC.]{2,3}\s+subtitles\s+/m.test(output);
  subtitleFilterCache.set(ffmpegPath, supported);
  return supported;
}

function getSubtitleDependencyMessage() {
  return "当前 ffmpeg 缺少 subtitles/libass 滤镜。请安装 Homebrew ffmpeg-full：brew install ffmpeg-full";
}

function parseSsim(output) {
  const matches = [...output.matchAll(/All:(\d\.\d+)/g)];
  if (!matches.length) return null;
  return Number.parseFloat(matches[matches.length - 1][1]);
}

async function runFfmpeg(paths, args, totalSeconds = 0) {
  return runProcess(paths.ffmpeg, ["-hide_banner", ...args], {
    collect: true,
    totalSeconds
  });
}

function runProcess(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const task = options.trackTask === false ? null : activeTask;
    if (task && task.cancelled) {
      reject(new Error("任务已取消"));
      return;
    }

    let output = "";
    let recent = "";
    let timedOut = false;
    const startedAt = Date.now();
    const child = spawn(command, args, {
      stdio: ["ignore", "pipe", "pipe"]
    });
    const timeout = options.timeoutMs
      ? setTimeout(() => {
          timedOut = true;
          child.kill("SIGTERM");
        }, options.timeoutMs)
      : null;

    if (task) task.process = child;

    child.stdout.on("data", (chunk) => {
      const text = chunk.toString();
      output += text;
      if (!options.collect) emitTask({ type: "log", level: "plain", message: text.trim() });
    });

    child.stderr.on("data", (chunk) => {
      const text = chunk.toString();
      output += text;
      recent += text;
      const parts = recent.split(/\r|\n/);
      recent = parts.pop() || "";
      if (!options.silent) {
        for (const part of parts) handleProcessLine(part, options.totalSeconds, startedAt);
        handleProcessLine(recent, options.totalSeconds, startedAt, true);
      }
    });

    child.on("error", (error) => {
      if (timeout) clearTimeout(timeout);
      reject(error);
    });
    child.on("close", (code, signal) => {
      if (timeout) clearTimeout(timeout);
      if (task && task.process === child) task.process = null;
      if (timedOut) {
        reject(new Error("字幕预览超时"));
        return;
      }
      if (task && task.cancelled) {
        reject(new Error("任务已取消"));
        return;
      }
      if (code === 0) {
        resolve({ code, signal, output });
        return;
      }
      const tail = output.split(/\r?\n|\r/).filter(Boolean).slice(-15).join("\n");
      reject(new Error(`ffmpeg 异常退出 (代码: ${code})${tail ? `\n${tail}` : ""}`));
    });
  });
}

function handleProcessLine(rawLine, totalSeconds, startedAt, transient = false) {
  const line = rawLine.trim();
  if (!line) return;

  const timeMatch = line.match(/time=(\d{2}):(\d{2}):(\d{2}\.\d+)/);
  if (timeMatch) {
    const currentSeconds = Number(timeMatch[1]) * 3600 + Number(timeMatch[2]) * 60 + Number(timeMatch[3]);
    const speedMatch = line.match(/speed=\s*([\d.]+x)/);
    const elapsedSeconds = Math.max(1, (Date.now() - startedAt) / 1000);
    const percent = totalSeconds > 0 ? Math.min(100, (currentSeconds / totalSeconds) * 100) : 0;
    const remainingSeconds = totalSeconds > 0 && currentSeconds > 0 ? (elapsedSeconds / currentSeconds) * (totalSeconds - currentSeconds) : 0;
    emitTask({
      type: "progress",
      percent,
      elapsed: formatSeconds(elapsedSeconds),
      remaining: totalSeconds > 0 ? formatSeconds(Math.max(0, remainingSeconds)) : "--:--:--",
      speed: speedMatch ? speedMatch[1] : "--",
      transient
    });
    return;
  }

  if (/error|failed/i.test(line) && !/showspectrumpic/i.test(line)) {
    emitTask({ type: "log", level: "warn", message: line });
  }
}

function formatSeconds(seconds) {
  const total = Math.max(0, Math.floor(seconds));
  const h = String(Math.floor(total / 3600)).padStart(2, "0");
  const m = String(Math.floor((total % 3600) / 60)).padStart(2, "0");
  const s = String(total % 60).padStart(2, "0");
  return `${h}:${m}:${s}`;
}
