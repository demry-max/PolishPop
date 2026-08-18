import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.dirname(scriptDirectory);
const iconsetDirectory = path.join(projectRoot, "Support", "AppIcon.iconset");
const outputPath = path.join(projectRoot, "Support", "PolishPop.icns");

const representations = [
  ["icp4", "icon_16x16.png"],
  ["icp5", "icon_32x32.png"],
  ["icp6", "icon_32x32@2x.png"],
  ["ic07", "icon_128x128.png"],
  ["ic08", "icon_256x256.png"],
  ["ic09", "icon_512x512.png"],
  ["ic10", "icon_512x512@2x.png"],
];

const chunks = representations.map(([type, filename]) => {
  const png = fs.readFileSync(path.join(iconsetDirectory, filename));
  const header = Buffer.alloc(8);
  header.write(type, 0, 4, "ascii");
  header.writeUInt32BE(header.length + png.length, 4);
  return Buffer.concat([header, png]);
});

const body = Buffer.concat(chunks);
const header = Buffer.alloc(8);
header.write("icns", 0, 4, "ascii");
header.writeUInt32BE(header.length + body.length, 4);
fs.writeFileSync(outputPath, Buffer.concat([header, body]));

console.log(outputPath);
