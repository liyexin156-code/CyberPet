import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";

const outDir = path.join(process.cwd(), "Assets", "pet");
fs.mkdirSync(outDir, { recursive: true });

const states = [
  ["idle", 4, [38, 166, 154, 255], [236, 72, 153, 255]],
  ["walk", 4, [34, 197, 94, 255], [236, 72, 153, 255]],
  ["happy", 4, [234, 179, 8, 255], [249, 115, 22, 255]],
  ["eat", 4, [45, 212, 191, 255], [146, 64, 14, 255]],
  ["drink", 3, [6, 182, 212, 255], [37, 99, 235, 255]],
  ["listless", 2, [107, 114, 128, 255], [99, 102, 241, 255]],
  ["sleep", 2, [168, 85, 247, 255], [59, 130, 246, 255]],
];

for (const [name, frames, body, accent] of states) {
  const width = 64 * frames;
  const height = 64;
  const pixels = Buffer.alloc(width * height * 4, 0);

  for (let frame = 0; frame < frames; frame += 1) {
    const x = frame * 64;
    const bob = name === "idle" ? frame % 2 : Math.abs((frame % 4) - 1);
    const yOffset = name === "happy" ? [0, 5, 9, 4][frame % 4] : bob;

    rect(pixels, width, x + 18, 20 + yOffset, 30, 24, body);
    rect(pixels, width, x + 42, 28 + yOffset, 12, 12, body);
    rect(pixels, width, x + 23, 40 + yOffset, 8, 8, accent);
    rect(pixels, width, x + 48, 36 + yOffset, 4, 5, accent);
    rect(pixels, width, x + 48, 34 + yOffset, 3, 3, [255, 255, 255, 255]);
    rect(pixels, width, x + 49, 35 + yOffset, 1, 1, [0, 0, 0, 255]);
    rect(pixels, width, x + 52, 31 + yOffset, 2, 2, [0, 0, 0, 255]);

    const legShift = name === "walk" ? (frame % 2 === 0 ? 3 : -1) : 0;
    rect(pixels, width, x + 23 + legShift, 14 + yOffset, 5, 8, body);
    rect(pixels, width, x + 39 - legShift, 14 + yOffset, 5, 8, body);

    const tailLift = name === "happy" ? 10 : 4 + (name === "listless" ? -6 : frame % 2);
    rect(pixels, width, x + 13, 33 + yOffset + tailLift, 7, 4, accent);

    if (name === "eat") {
      rect(pixels, width, x + 45, 12, 13, 5, [146, 64, 14, 255]);
    } else if (name === "drink") {
      rect(pixels, width, x + 45, 12, 13, 5, [37, 99, 235, 255]);
    } else if (name === "sleep") {
      rect(pixels, width, x + 48, 50, 4, 2, [255, 255, 255, 255]);
      rect(pixels, width, x + 52, 54, 5, 2, [255, 255, 255, 255]);
    }
  }

  fs.writeFileSync(path.join(outDir, `${name}.png`), png(width, height, pixels));
}

function rect(pixels, width, x, y, w, h, rgba) {
  for (let row = Math.max(0, y); row < Math.min(64, y + h); row += 1) {
    for (let col = Math.max(0, x); col < Math.min(width, x + w); col += 1) {
      const i = (row * width + col) * 4;
      pixels[i] = rgba[0];
      pixels[i + 1] = rgba[1];
      pixels[i + 2] = rgba[2];
      pixels[i + 3] = rgba[3];
    }
  }
}

function png(width, height, pixels) {
  const scanlineLength = width * 4 + 1;
  const raw = Buffer.alloc(scanlineLength * height);

  for (let y = 0; y < height; y += 1) {
    raw[y * scanlineLength] = 0;
    pixels.copy(raw, y * scanlineLength + 1, y * width * 4, (y + 1) * width * 4);
  }

  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk("IHDR", Buffer.concat([u32(width), u32(height), Buffer.from([8, 6, 0, 0, 0])])),
    chunk("IDAT", zlib.deflateSync(raw)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

function chunk(type, data) {
  const typeBuffer = Buffer.from(type, "ascii");
  return Buffer.concat([u32(data.length), typeBuffer, data, u32(crc32(Buffer.concat([typeBuffer, data])) >>> 0)]);
}

function u32(value) {
  const buffer = Buffer.alloc(4);
  buffer.writeUInt32BE(value >>> 0);
  return buffer;
}

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}
