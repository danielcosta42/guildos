#!/usr/bin/env node
// Renders the Winter Veil snow globe images the addon shows (issue #437; the site's specs/119 §13).
// The game cannot load 3D from outside, so each scene x rarity is a still taken from the approved prototype
// (guildos-web: specs/119-o-amigo-secreto/prototipo-globo.html, three.js r128, drawn entirely in code) and written
// as a 128x128 32-bit uncompressed TGA (power of two, top-left origin), plus one closed (wrapped) globe.
//
//   node tools/render-globes.js <path to prototipo-globo.html> [out dir, default Media/Globes]
//
// Needs Playwright with Chromium and network access to cdnjs (the prototype loads three.js from there).
// 5 scenes x 4 rarities = 20 files `<scene>-<rarity>.tga` (tree|cabin|snowman|fire|mountain x
// common|rare|epic|legendary) and `closed.tga`. Reduced motion is forced so the globe stands still at a fixed angle.
"use strict";
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const SIZE = 128;
// addon id -> the prototype's chip id
const SCENES = { tree: "arvore", cabin: "cabana", snowman: "boneco", fire: "fogueira", mountain: "montanha" };
const RARITIES = { common: "comum", rare: "rara", epic: "epica", legendary: "lendaria" };

function tga(rgba, size) {
  const head = Buffer.alloc(18);
  head[2] = 2; // uncompressed true colour
  head.writeUInt16LE(size, 12);
  head.writeUInt16LE(size, 14);
  head[16] = 32;
  head[17] = 0x28; // 8 alpha bits, origin top-left
  const body = Buffer.alloc(size * size * 4);
  for (let i = 0; i < size * size; i++) {
    body[i * 4] = rgba[i * 4 + 2]; // B
    body[i * 4 + 1] = rgba[i * 4 + 1]; // G
    body[i * 4 + 2] = rgba[i * 4]; // R
    body[i * 4 + 3] = rgba[i * 4 + 3];
  }
  return Buffer.concat([head, body]);
}

// The globe canvas, cropped square and reduced to SIZE in the page (no image library needed).
async function grab(page, overlay) {
  const png = await page.locator(".globe").screenshot({ animations: "disabled" });
  const data = await page.evaluate(async ({ b64, size, overlay }) => {
    const img = new Image();
    img.src = "data:image/png;base64," + b64;
    await img.decode();
    const c = document.createElement("canvas");
    c.width = c.height = size;
    const g = c.getContext("2d");
    g.imageSmoothingQuality = "high";
    const s = Math.min(img.width, img.height);
    g.drawImage(img, (img.width - s) / 2, (img.height - s) / 2, s, s, 0, 0, size, size);
    if (overlay) {
      // The wrapping: two gold bands across the globe and a bow on top.
      g.strokeStyle = "#d9a94f";
      g.lineWidth = size * 0.07;
      g.beginPath();
      g.moveTo(0, size * 0.58); g.lineTo(size, size * 0.58);
      g.moveTo(size / 2, size * 0.14); g.lineTo(size / 2, size);
      g.stroke();
      g.lineWidth = size * 0.045;
      g.beginPath();
      g.ellipse(size * 0.4, size * 0.12, size * 0.1, size * 0.06, -0.5, 0, 6.3);
      g.ellipse(size * 0.6, size * 0.12, size * 0.1, size * 0.06, 0.5, 0, 6.3);
      g.stroke();
    }
    return Array.from(g.getImageData(0, 0, size, size).data);
  }, { b64: png.toString("base64"), size: SIZE, overlay: !!overlay });
  return Buffer.from(data);
}

(async () => {
  const proto = process.argv[2];
  const out = path.resolve(process.argv[3] || path.join(__dirname, "..", "Media", "Globes"));
  if (!proto || !fs.existsSync(proto)) {
    console.error("usage: node tools/render-globes.js <prototipo-globo.html> [out dir]");
    process.exit(2);
  }
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch({ args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"] });
  const page = await browser.newPage({ viewport: { width: 1400, height: 1000 }, reducedMotion: "reduce", deviceScaleFactor: 1 });
  await page.goto(pathToUrl(proto), { waitUntil: "networkidle" });
  // Only the globe: no hint, no controls beside it, and the card's plate stays as the prototype draws it.
  await page.addStyleTag({ content: ".hint,header,.foot{display:none!important}.panel{position:fixed!important;left:-5000px!important}.wrap{padding:0!important}.stage{display:block!important}.globe{width:640px;height:640px;max-height:none!important;flex:none!important}" });
  let n = 0;
  for (const [scene, sid] of Object.entries(SCENES)) {
    for (const [rarity, rid] of Object.entries(RARITIES)) {
      await page.dispatchEvent(`#scenes .chip[data-id="${sid}"]`, "click");
      await page.dispatchEvent(`#rarities .chip[data-id="${rid}"]`, "click");
      await page.waitForTimeout(2500); // the snow settles
      fs.writeFileSync(path.join(out, `${scene}-${rarity}.tga`), tga(await grab(page, false), SIZE));
      n++;
    }
  }
  // The wrapped globe: one image, the common tree under its ribbon (nothing of the scene or rarity shows).
  await page.dispatchEvent('#scenes .chip[data-id="arvore"]', "click");
  await page.dispatchEvent('#rarities .chip[data-id="comum"]', "click");
  await page.waitForTimeout(2500);
  fs.writeFileSync(path.join(out, "closed.tga"), tga(await grab(page, true), SIZE));
  await browser.close();
  console.log(`${n + 1} images in ${out}`);
})().catch((e) => { console.error(e); process.exit(1); });

function pathToUrl(p) { return "file://" + path.resolve(p); }
