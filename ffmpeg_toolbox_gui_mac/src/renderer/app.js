const state = {
  primaryFile: "",
  secondaryFile: "",
  lastOutputPath: "",
  busy: false,
  dependenciesOk: false
};

const els = {
  dependencyStatus: document.querySelector("#dependencyStatus"),
  refreshStatusButton: document.querySelector("#refreshStatusButton"),
  dropZone: document.querySelector("#dropZone"),
  primaryName: document.querySelector("#primaryName"),
  fileMeta: document.querySelector("#fileMeta"),
  chooseFileButton: document.querySelector("#chooseFileButton"),
  clearSecondButton: document.querySelector("#clearSecondButton"),
  cancelButton: document.querySelector("#cancelButton"),
  revealOutputButton: document.querySelector("#revealOutputButton"),
  progressFill: document.querySelector("#progressFill"),
  progressText: document.querySelector("#progressText"),
  logBox: document.querySelector("#logBox"),
  fontNameInput: document.querySelector("#fontNameInput")
};

const compareActions = new Set(["ssim", "diff", "quality"]);

window.toolbox.onTaskEvent((event) => {
  if (event.type === "started") {
    state.busy = true;
    state.lastOutputPath = "";
    setBusy(true);
    setProgress(0, "运行中");
    return;
  }

  if (event.type === "progress") {
    const percentText = event.percent ? `${event.percent.toFixed(1)}%` : "处理中";
    setProgress(event.percent || 0, `${percentText} | 耗时 ${event.elapsed} | 剩余 ${event.remaining} | 速度 ${event.speed}`);
    return;
  }

  if (event.type === "log") {
    appendLog(event.message, event.level);
    return;
  }

  if (event.type === "done") {
    state.busy = false;
    state.lastOutputPath = event.outputPath || "";
    setBusy(false);
    setProgress(event.ok ? 100 : 0, event.ok ? "完成" : "失败");
    if (event.message) appendLog(event.message, event.ok ? "success" : "error");
    els.revealOutputButton.disabled = !state.lastOutputPath;
  }
});

els.refreshStatusButton.addEventListener("click", refreshStatus);
els.chooseFileButton.addEventListener("click", chooseFiles);
els.clearSecondButton.addEventListener("click", () => {
  state.secondaryFile = "";
  updateFileDisplay();
  appendLog("对比文件已清除", "info");
});
els.cancelButton.addEventListener("click", () => window.toolbox.cancelTask());
els.revealOutputButton.addEventListener("click", () => {
  if (state.lastOutputPath) window.toolbox.revealPath(state.lastOutputPath);
});

document.querySelectorAll("[data-action]").forEach((button) => {
  button.addEventListener("click", () => runAction(button.dataset.action));
});

els.dropZone.addEventListener("dragover", (event) => {
  event.preventDefault();
  els.dropZone.classList.add("dragging");
});

els.dropZone.addEventListener("dragleave", () => {
  els.dropZone.classList.remove("dragging");
});

els.dropZone.addEventListener("drop", (event) => {
  event.preventDefault();
  els.dropZone.classList.remove("dragging");
  const files = Array.from(event.dataTransfer.files).map((file) => window.toolbox.filePath(file)).filter(Boolean);
  setSelectedFiles(files);
});

async function refreshStatus() {
  const result = await window.toolbox.getStatus();
  state.dependenciesOk = result.ok;
  if (result.ok) {
    els.dependencyStatus.textContent = `ffmpeg: ${result.paths.ffmpeg}    ffprobe: ${result.paths.ffprobe}`;
  } else {
    els.dependencyStatus.textContent = "未找到 ffmpeg / ffprobe，请先安装并加入 PATH";
  }
  updateActionButtons();
}

async function chooseFiles() {
  const files = await window.toolbox.selectVideoFiles();
  setSelectedFiles(files);
}

function setSelectedFiles(files) {
  if (!files.length) return;
  state.primaryFile = files[0] || "";
  state.secondaryFile = files[1] || "";
  state.lastOutputPath = "";
  updateFileDisplay();
  els.revealOutputButton.disabled = true;
}

function updateFileDisplay() {
  if (!state.primaryFile) {
    els.primaryName.textContent = "未选择视频文件";
    els.fileMeta.textContent = "拖入或选择视频文件";
  } else {
    els.primaryName.textContent = basename(state.primaryFile);
    els.fileMeta.textContent = state.secondaryFile ? `${state.primaryFile}    对比: ${basename(state.secondaryFile)}` : state.primaryFile;
  }
  updateActionButtons();
}

async function runAction(action) {
  if (state.busy) return;
  if (!state.dependenciesOk) {
    appendLog("未找到 ffmpeg / ffprobe", "warn");
    return;
  }
  if (!state.primaryFile) {
    appendLog("请先选择视频文件", "warn");
    return;
  }

  let subtitleFile = "";
  if (compareActions.has(action) && !state.secondaryFile) {
    const files = await window.toolbox.selectVideoFiles();
    if (!files.length) {
      appendLog("请选择对比文件", "warn");
      return;
    }
    state.secondaryFile = files[0];
    updateFileDisplay();
  }

  if (action === "subtitle") {
    subtitleFile = await window.toolbox.selectSubtitleFile();
    if (!subtitleFile) return;
  }

  clearLog();
  const result = await window.toolbox.startTask({
    action,
    primaryFile: state.primaryFile,
    secondaryFile: state.secondaryFile,
    subtitleFile,
    fontName: els.fontNameInput.value.trim() || "Microsoft YaHei"
  });

  if (!result.ok) appendLog(result.message, "error");
}

function setBusy(busy) {
  state.busy = busy;
  els.cancelButton.disabled = !busy;
  els.chooseFileButton.disabled = busy;
  els.clearSecondButton.disabled = busy;
  els.refreshStatusButton.disabled = busy;
  updateActionButtons();
}

function updateActionButtons() {
  document.querySelectorAll("[data-action]").forEach((button) => {
    button.disabled = state.busy || !state.dependenciesOk || !state.primaryFile;
  });
}

function setProgress(percent, text) {
  els.progressFill.style.width = `${Math.max(0, Math.min(100, percent))}%`;
  els.progressText.textContent = text;
}

function appendLog(message, level = "plain") {
  const prefix = level === "warn" ? "[!]" : level === "error" ? "[X]" : level === "success" ? "[OK]" : "";
  const line = prefix ? `${prefix} ${message}` : message;
  els.logBox.textContent += `${line}\n`;
  els.logBox.scrollTop = els.logBox.scrollHeight;
}

function clearLog() {
  els.logBox.textContent = "";
  setProgress(0, "运行中");
}

function basename(filePath) {
  return filePath.split(/[\\/]/).filter(Boolean).pop() || filePath;
}

refreshStatus();
updateFileDisplay();
