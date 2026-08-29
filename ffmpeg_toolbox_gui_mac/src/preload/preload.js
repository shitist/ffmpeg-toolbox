const { contextBridge, ipcRenderer, webUtils } = require("electron");

contextBridge.exposeInMainWorld("toolbox", {
  getStatus: () => ipcRenderer.invoke("toolbox:get-status"),
  filePath: (file) => webUtils.getPathForFile(file),
  selectVideoFiles: () => ipcRenderer.invoke("toolbox:select-video-files"),
  selectSubtitleFile: () => ipcRenderer.invoke("toolbox:select-subtitle-file"),
  getSubtitleFonts: () => ipcRenderer.invoke("toolbox:get-subtitle-fonts"),
  previewSubtitle: (request) => ipcRenderer.invoke("toolbox:preview-subtitle", request),
  startTask: (request) => ipcRenderer.invoke("toolbox:start-task", request),
  cancelTask: () => ipcRenderer.invoke("toolbox:cancel-task"),
  revealPath: (filePath) => ipcRenderer.invoke("toolbox:reveal-path", filePath),
  onTaskEvent: (callback) => {
    const listener = (_event, payload) => callback(payload);
    ipcRenderer.on("toolbox:task-event", listener);
    return () => ipcRenderer.removeListener("toolbox:task-event", listener);
  }
});
