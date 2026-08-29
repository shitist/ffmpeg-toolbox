const SUBTITLE_FONT_PRESETS = Object.freeze([
  Object.freeze({
    id: "noto-sc",
    displayName: "Noto Sans 中文（默认）",
    fontName: "Noto Sans CJK SC",
    srtScale: 1.1
  }),
  Object.freeze({
    id: "noto-jp",
    displayName: "Noto Sans 日文",
    fontName: "Noto Sans CJK JP",
    srtScale: 1.1
  })
]);

function listSubtitleFonts() {
  return SUBTITLE_FONT_PRESETS.map(({ id, displayName }) => ({ id, displayName }));
}

function getSubtitleFontPreset(fontId) {
  return SUBTITLE_FONT_PRESETS.find((preset) => preset.id === fontId) || SUBTITLE_FONT_PRESETS[0];
}

function applySubtitleFont(content, preset, plainText) {
  const newline = content.includes("\r\n") ? "\r\n" : "\n";
  const lines = content.split(/\r?\n/);
  let inStyles = false;
  let columns = [];

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    const section = line.match(/^\s*\[([^\]]+)]/);
    if (section) {
      inStyles = section[1].trim().toLowerCase() === "v4+ styles";
      columns = [];
      continue;
    }

    const format = inStyles && line.match(/^Format:\s*(.+)$/i);
    if (format) {
      columns = format[1].split(",").map((column) => column.trim().toLowerCase());
      continue;
    }

    const style = inStyles && columns.length > 0 && line.match(/^(Style:\s*)(.*)$/i);
    if (!style) continue;

    const fields = style[2].split(",");
    const nameIndex = columns.indexOf("name");
    const fontIndex = columns.indexOf("fontname");
    if (fields.length !== columns.length || nameIndex < 0 || fontIndex < 0) continue;
    if (fields[nameIndex].trim().toLowerCase() !== "default") continue;

    fields[fontIndex] = preset.fontName;
    const sizeIndex = columns.indexOf("fontsize");
    if (plainText && sizeIndex >= 0) {
      const fontSize = Number.parseFloat(fields[sizeIndex]);
      if (Number.isFinite(fontSize)) {
        fields[sizeIndex] = formatNumber(fontSize * preset.srtScale);
      }
    }
    lines[index] = `${style[1]}${fields.join(",")}`;
  }

  return lines.join(newline);
}

function getSubtitlePreviewTime(content) {
  const lines = content.split(/\r?\n/);
  let inEvents = false;
  let columns = [];

  for (const line of lines) {
    const section = line.match(/^\s*\[([^\]]+)]/);
    if (section) {
      inEvents = section[1].trim().toLowerCase() === "events";
      columns = [];
      continue;
    }

    const format = inEvents && line.match(/^Format:\s*(.+)$/i);
    if (format) {
      columns = format[1].split(",").map((column) => column.trim().toLowerCase());
      continue;
    }

    const dialogue = inEvents && columns.length > 0 && line.match(/^Dialogue:\s*(.*)$/i);
    if (!dialogue) continue;

    const fields = splitFields(dialogue[1], columns.length);
    const startIndex = columns.indexOf("start");
    const endIndex = columns.indexOf("end");
    const textIndex = columns.indexOf("text");
    if (fields.length !== columns.length || startIndex < 0 || endIndex < 0 || textIndex < 0) continue;

    const visibleText = fields[textIndex]
      .replace(/\{[^}]*}/g, "")
      .replace(/\\[Nnh]/g, " ")
      .trim();
    if (!visibleText) continue;

    const start = parseAssTime(fields[startIndex]);
    const end = parseAssTime(fields[endIndex]);
    if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) continue;
    return Math.max(0, start + Math.min(0.5, (end - start) / 2));
  }

  return null;
}

function buildSubtitleFilter(subtitlePath, fontDirectory) {
  return `subtitles=filename=${quoteFilterValue(subtitlePath)}:fontsdir=${quoteFilterValue(fontDirectory)}`;
}

function quoteFilterValue(value) {
  const normalized = value.replace(/\\/g, "/").replace(/:/g, "\\:");
  return `'${normalized.replace(/'/g, "'\\\\''")}'`;
}

function splitFields(value, count) {
  const fields = [];
  let offset = 0;
  for (let index = 1; index < count; index += 1) {
    const comma = value.indexOf(",", offset);
    if (comma < 0) return [];
    fields.push(value.slice(offset, comma));
    offset = comma + 1;
  }
  fields.push(value.slice(offset));
  return fields;
}

function parseAssTime(value) {
  const match = value.trim().match(/^(\d+):(\d{1,2}):(\d{1,2})(?:\.(\d+))?$/);
  if (!match) return Number.NaN;
  const fraction = match[4] ? Number(`0.${match[4]}`) : 0;
  return Number(match[1]) * 3600 + Number(match[2]) * 60 + Number(match[3]) + fraction;
}

function formatNumber(value) {
  return value.toFixed(3).replace(/\.0+$|(?<=\.[0-9]*?)0+$/g, "");
}

module.exports = {
  applySubtitleFont,
  buildSubtitleFilter,
  getSubtitleFontPreset,
  getSubtitlePreviewTime,
  listSubtitleFonts
};
