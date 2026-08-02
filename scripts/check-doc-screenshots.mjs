import { readFile } from "node:fs/promises";

const screenshotDirectory = new URL("../docs/assets/screenshots/", import.meta.url);
const expectedFiles = [
  "overview-light.webp",
  "overview-dark.webp",
  "client-settings-light.webp",
  "client-settings-dark.webp",
  "task-settings-light.webp",
  "task-settings-dark.webp",
];
const expectedWidth = 2360;
const expectedHeight = 1560;

function readChunkNamesAndCanvas(data, fileName) {
  if (data.length < 30 || data.toString("ascii", 0, 4) !== "RIFF" || data.toString("ascii", 8, 12) !== "WEBP") {
    throw new Error(`${fileName}: 不是有效的 WebP 文件`);
  }

  const chunks = [];
  let canvas;
  let hasAlpha = false;
  for (let offset = 12; offset + 8 <= data.length;) {
    const name = data.toString("ascii", offset, offset + 4);
    const size = data.readUInt32LE(offset + 4);
    const payload = offset + 8;
    if (payload + size > data.length) {
      throw new Error(`${fileName}: WebP chunk ${name} 已截断`);
    }
    chunks.push(name);
    if (name === "VP8X") {
      if (size < 10) throw new Error(`${fileName}: VP8X chunk 无效`);
      hasAlpha = (data[payload] & 0x10) !== 0;
      canvas = {
        width: data.readUIntLE(payload + 4, 3) + 1,
        height: data.readUIntLE(payload + 7, 3) + 1,
      };
    } else if (name === "VP8L") {
      if (size < 5 || data[payload] !== 0x2f) throw new Error(`${fileName}: VP8L chunk 无效`);
      const bits = data.readUInt32LE(payload + 1);
      canvas = {
        width: (bits & 0x3fff) + 1,
        height: ((bits >>> 14) & 0x3fff) + 1,
      };
      hasAlpha = ((bits >>> 28) & 1) === 1;
    }
    offset = payload + size + (size % 2);
  }
  return { chunks, canvas, hasAlpha };
}

const failures = [];
for (const fileName of expectedFiles) {
  try {
    const data = await readFile(new URL(fileName, screenshotDirectory));
    const { chunks, canvas, hasAlpha } = readChunkNamesAndCanvas(data, fileName);
    if (!chunks.includes("VP8L") || chunks.includes("VP8 ")) {
      failures.push(`${fileName}: 必须使用无损 WebP（VP8L）`);
    }
    if (canvas?.width !== expectedWidth || canvas?.height !== expectedHeight) {
      failures.push(`${fileName}: 应为 ${expectedWidth} × ${expectedHeight}，实际为 ${canvas?.width ?? "未知"} × ${canvas?.height ?? "未知"}`);
    }
    if (!hasAlpha) {
      failures.push(`${fileName}: 必须保留透明窗口圆角`);
    }
  } catch (error) {
    failures.push(error instanceof Error ? error.message : String(error));
  }
}

if (failures.length > 0) {
  console.error(failures.join("\n"));
  process.exitCode = 1;
} else {
  console.log(`Verified ${expectedFiles.length} lossless Retina screenshots (${expectedWidth} × ${expectedHeight}, alpha).`);
}
