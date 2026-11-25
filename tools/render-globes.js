#!/usr/bin/env node
// Renders the Winter Veil snow globe images the addon shows (issue #437; the site's specs/119 §13).
// The game cannot load 3D from outside, so each scene x rarity is a still taken from the approved prototype
// (guildos-web: specs/119-o-amigo-secreto/prototipo-globo.html, three.js r128, drawn entirely in code) and written
// as a 32-bit uncompressed TGA (power of two, top-left origin) with a REAL alpha channel (transparent background,
// no plate, no halo), at 128 px (<out>/) and 256 px (<out>/256/), plus the closed globe: frosted glass over the same
// base, with no scene and no ribbon (the receiver must not see the scene before opening; site spec 119 §9).
//
//   node tools/render-globes.js <path to prototipo-globo.html> [out dir, default Media/Globes]
//
// Needs Playwright with Chromium and network access to cdnjs (the prototype loads three.js from there).
// 5 scenes x 4 rarities = 20 files `<scene>-<rarity>.tga` (tree|cabin|snowman|fire|mountain x
// common|rare|epic|legendary) and `closed.tga` / `closed-256.tga`. Reduced motion is forced so the globe stands still
// at a fixed angle. The wrapped state of the gift is a box now (tools/render-veil-assets.js, Veil/giftbox).
"use strict";
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const SIZES = [128, 256];
// addon id -> the prototype's chip id
const SCENES = { tree: "arvore", cabin: "cabana", snowman: "boneco", fire: "fogueira", mountain: "montanha" };
// sphere of the glass in the 640 px capture, as fractions of the image (centre y, radius); measured from the prototype
const FROST = { cy: 0.42, R: 0.357 };
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
module.exports = { tga };
if (require.main !== module) return;

// The globe canvas on a transparent page, cropped to the globe's box and reduced in the page (no image library).
// `frost` paints milky glass over the sphere (scene hidden); the base below it stays as rendered.
async function grab(page, sizes, frost) {
  const png = await page.locator(".globe").screenshot({ animations: "disabled", omitBackground: true });
  const data = await page.evaluate(async ({ b64, sizes, frost }) => {
    const img = new Image();
    img.src = "data:image/png;base64," + b64;
    await img.decode();
    const s = Math.min(img.width, img.height), ox = (img.width - s) / 2, oy = (img.height - s) / 2;
    const src = document.createElement("canvas");
    src.width = src.height = s;
    const sg = src.getContext("2d");
    sg.drawImage(img, ox, oy, s, s, 0, 0, s, s);
    if (frost) {
      // find the sphere: the glass is the roundest, widest part above the base; measured from the opaque rows
      const px = sg.getImageData(0, 0, s, s).data;
      let top = s, bot = 0, left = s, right = 0;
      for (let y = 0; y < s; y++) for (let x = 0; x < s; x++) if (px[(y * s + x) * 4 + 3] > 40) { top = Math.min(top, y); bot = Math.max(bot, y); left = Math.min(left, x); right = Math.max(right, x); }
      const cx = (left + right) / 2, R = frost.R * s, cy = frost.cy * s;
      const tmp = document.createElement("canvas");
      tmp.width = tmp.height = s;
      const g = tmp.getContext("2d");
      g.filter = `blur(${s * 0.03}px)`;
      g.drawImage(src, 0, 0);
      g.filter = "none";
      g.globalCompositeOperation = "destination-in";
      g.beginPath(); g.arc(cx, cy, R, 0, 7); g.fill();
      g.globalCompositeOperation = "source-over";
      const mk = g.createRadialGradient(cx - R * 0.25, cy - R * 0.3, R * 0.05, cx, cy, R);
      mk.addColorStop(0, "rgba(246,250,255,0.97)"); mk.addColorStop(0.6, "rgba(214,228,242,0.96)"); mk.addColorStop(1, "rgba(150,178,206,0.97)");
      g.save(); g.beginPath(); g.arc(cx, cy, R, 0, 7); g.clip(); g.fillStyle = mk; g.fillRect(0, 0, s, s);
      const hl = g.createRadialGradient(cx - R * 0.38, cy - R * 0.45, 0, cx - R * 0.38, cy - R * 0.45, R * 0.4);
      hl.addColorStop(0, "rgba(255,255,255,0.75)"); hl.addColorStop(1, "rgba(255,255,255,0)");
      g.fillStyle = hl; g.fillRect(0, 0, s, s); g.restore();
      g.strokeStyle = "rgba(255,255,255,0.55)"; g.lineWidth = s * 0.006; g.beginPath(); g.arc(cx, cy, R - s * 0.004, 0, 7); g.stroke();
      // the globe without the sphere area (so the base shows as rendered, the scene never does), then the frost
      sg.save(); sg.globalCompositeOperation = "destination-out"; sg.beginPath(); sg.arc(cx, cy, R + s * 0.003, 0, 7); sg.fill(); sg.restore();
      sg.drawImage(tmp, 0, 0);
    }
    const out = {};
    for (const size of sizes) {
      // stepwise halving keeps edges clean (a straight 640 -> 128 would alias the thin glass rim)
      let cur = src, w = s;
      while (w / 2 >= size) { const c = document.createElement("canvas"); c.width = c.height = w / 2; const cg = c.getContext("2d"); cg.imageSmoothingQuality = "high"; cg.drawImage(cur, 0, 0, w / 2, w / 2); cur = c; w /= 2; }
      const c = document.createElement("canvas"); c.width = c.height = size;
      const cg = c.getContext("2d"); cg.imageSmoothingQuality = "high"; cg.drawImage(cur, 0, 0, size, size);
      out[size] = Array.from(cg.getImageData(0, 0, size, size).data);
    }
    return out;
  }, { b64: png.toString("base64"), sizes, frost });
  const r = {};
  for (const k of Object.keys(data)) r[k] = Buffer.from(data[k]);
  return r;
}

(async () => {
  const proto = process.argv[2];
  const out = path.resolve(process.argv[3] || path.join(__dirname, "..", "Media", "Globes"));
  if (!proto || !fs.existsSync(proto)) {
    console.error("usage: node tools/render-globes.js <prototipo-globo.html> [out dir]");
    process.exit(2);
  }
  fs.mkdirSync(path.join(out, "256"), { recursive: true });
  const browser = await chromium.launch({ args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"] });
  const page = await browser.newPage({ viewport: { width: 1400, height: 1000 }, reducedMotion: "reduce", deviceScaleFactor: 1 });
  await page.goto(pathToUrl(proto), { waitUntil: "networkidle" });
  // Only the globe, on nothing: no plate behind it, no hint, no controls, a clear page.
  await page.addStyleTag({ content: "html,body,.wrap,.stage{background:none!important}.hint,header,.foot{display:none!important}.panel{position:fixed!important;left:-5000px!important}.wrap{padding:0!important}.stage{display:block!important}.globe{width:640px;height:640px;max-height:none!important;flex:none!important;background:none!important;border:0!important;box-shadow:none!important;border-radius:0!important}" });
  const put = (name, bufs) => {
    fs.writeFileSync(path.join(out, `${name}.tga`), tga(bufs[128], 128));
    fs.writeFileSync(path.join(out, "256", `${name}.tga`), tga(bufs[256], 256));
  };
  let n = 0;
  for (const [scene, sid] of Object.entries(SCENES)) {
    for (const [rarity, rid] of Object.entries(RARITIES)) {
      await page.dispatchEvent(`#scenes .chip[data-id="${sid}"]`, "click");
      await page.dispatchEvent(`#rarities .chip[data-id="${rid}"]`, "click");
      await page.waitForTimeout(2500); // the snow settles
      put(`${scene}-${rarity}`, await grab(page, SIZES, null));
      n++;
    }
  }
  // The closed globe: the plain common base under milky glass; no scene, no ribbon, no rarity tell. The 256 file is
  // named closed-256 (next to closed), not in 256/, as the spec lists it.
  await page.dispatchEvent('#scenes .chip[data-id="arvore"]', "click");
  await page.dispatchEvent('#rarities .chip[data-id="comum"]', "click");
  await page.waitForTimeout(2500);
  const closed = await grab(page, SIZES, FROST);
  fs.writeFileSync(path.join(out, "closed.tga"), tga(closed[128], 128));
  fs.writeFileSync(path.join(out, "closed-256.tga"), tga(closed[256], 256));
  await browser.close();
  console.log(`${n + 2} globes x2 sizes in ${out}`);
})().catch((e) => { console.error(e); process.exit(1); });

function pathToUrl(p) { return "file://" + path.resolve(p); }
