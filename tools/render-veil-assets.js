#!/usr/bin/env node
// Generates the Winter Veil screen assets of the addon (issue guildos-web#673, S3; site spec 122 addon.md "Assets"):
//
//   Media/Veil/chimney-cold.tga  256x512   the Chimney, cold, with snow (drawn at the bottom, top rows clear)
//   Media/Veil/chimney-hot.tga   256x512   the same drawing, embers palette; revealed from below by TexCoord
//   Media/Veil/veil-fx.tga       512x512   atlas: fire 8x128 (4x2), shake snow 4x128, rays/ring/flash 128, smoke 64,
//                                          star/ember/flake/ribbon 32, bow 128x64. White pieces, tinted by SetVertexColor
//   Media/Veil/frimm.tga         512x128   three faces (rush, happy, oops) + one free cell, 128 px each
//   Media/Veil/giftbox.tga, giftbox-256.tga          closed gift box (ribbon + bow), 128 and 256 px, transparent
//   Media/Veil/giftbox-open.tga, giftbox-open-256.tga  the same box with the lid off, floating beside it
//
//   node tools/render-veil-assets.js [out dir, default Media/Veil]
//
// 2D pieces are the code of the approved prototype (guildos-web specs/122-telas-do-evento/prototipo-addon.html:
// drawChimney, buildAtlas, frimm), copied here so the generator does not need the site repo. The box is three.js r128
// (cdnjs, as render-globes.js). Output is 32-bit uncompressed TGA, top-left origin, real alpha. Needs Playwright with
// Chromium and network access to cdnjs. Everything is deterministic (seeded) except WebGL anti-aliasing noise.
"use strict";
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");
const { tga } = require("./render-globes.js");

// ---- browser side: plain functions, serialised by Playwright ----------------------------------------------------

function rng(a){return()=>{a|=0;a=a+0x6D2B79F5|0;let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296}}

// Frimm: three faces. The drawing is the site's own (apps/web/components/frimm.tsx, the official Frimm, decided
// 2026-11-25), rendered still and set on a round dark plate so it reads on the addon's panel.
const FRIMM_SITE = {"rush": "<g class=\"f-body\"><g class=\"f-ear f-l\"><path d=\"M26 52 3 40 23 63Z\" fill=\"#e2ac80\"></path><path d=\"M24 53 10 45 23 59Z\" fill=\"#c98660\"></path></g><g class=\"f-ear f-r\"><path d=\"M70 52 93 40 73 63Z\" fill=\"#e2ac80\"></path><path d=\"M72 53 86 45 73 59Z\" fill=\"#c98660\"></path></g><circle cx=\"48\" cy=\"56\" r=\"23\" fill=\"#eebd93\"></circle><path d=\"M30 74Q48 86 66 74l3 9Q48 95 27 83Z\" fill=\"#c8423b\"></path><path d=\"M60 80l10 2-2 12-9-3Z\" fill=\"#a8322d\"></path><g class=\"f-hat\"><path d=\"M22 47Q24 18 50 13 70 9 86 22 74 22 68 29 75 39 74 47Q48 36 22 47Z\" fill=\"#2c6a44\"></path><path d=\"M36 22Q52 14 68 29\" stroke=\"#245a3a\" stroke-width=\"3\" fill=\"none\"></path><circle class=\"f-pom\" cx=\"87\" cy=\"23\" r=\"5.5\" fill=\"#f6f9ff\"></circle></g><path d=\"M21 45Q48 34 75 45v6Q48 40 21 51Z\" fill=\"#d9a94f\"></path><g class=\"f-eyes\"><circle cx=\"39\" cy=\"54\" r=\"5.5\" fill=\"#fff\"></circle><circle cx=\"57\" cy=\"54\" r=\"5.5\" fill=\"#fff\"></circle><circle class=\"f-pup\" cx=\"41\" cy=\"54.5\" r=\"2.4\" fill=\"#1b1a22\"></circle><circle class=\"f-pup\" cx=\"59\" cy=\"54.5\" r=\"2.4\" fill=\"#1b1a22\"></circle></g><path d=\"M33 45l9-2M54 43l9 2\" stroke=\"#6b4426\" stroke-width=\"2\" stroke-linecap=\"round\"></path><ellipse cx=\"48\" cy=\"67\" rx=\"3.5\" ry=\"4\" fill=\"#5a1d1a\"></ellipse><path class=\"f-drop\" d=\"M73 36q4 6 0 9-4-3 0-9Z\" fill=\"#7fe0ff\"></path></g>", "happy": "<g class=\"f-body\"><g class=\"f-ear f-l\"><path d=\"M26 52 3 40 23 63Z\" fill=\"#e2ac80\"></path><path d=\"M24 53 10 45 23 59Z\" fill=\"#c98660\"></path></g><g class=\"f-ear f-r\"><path d=\"M70 52 93 40 73 63Z\" fill=\"#e2ac80\"></path><path d=\"M72 53 86 45 73 59Z\" fill=\"#c98660\"></path></g><circle cx=\"48\" cy=\"56\" r=\"23\" fill=\"#eebd93\"></circle><path d=\"M30 74Q48 86 66 74l3 9Q48 95 27 83Z\" fill=\"#c8423b\"></path><path d=\"M60 80l10 2-2 12-9-3Z\" fill=\"#a8322d\"></path><g class=\"f-hat\"><path d=\"M22 47Q24 18 50 13 70 9 86 22 74 22 68 29 75 39 74 47Q48 36 22 47Z\" fill=\"#2c6a44\"></path><path d=\"M36 22Q52 14 68 29\" stroke=\"#245a3a\" stroke-width=\"3\" fill=\"none\"></path><circle class=\"f-pom\" cx=\"87\" cy=\"23\" r=\"5.5\" fill=\"#f6f9ff\"></circle></g><path d=\"M21 45Q48 34 75 45v6Q48 40 21 51Z\" fill=\"#d9a94f\"></path><g class=\"f-eyes\"><path d=\"M34 55q5-7 10 0M52 55q5-7 10 0\" stroke=\"#1b1a22\" stroke-width=\"2.4\" fill=\"none\" stroke-linecap=\"round\"></path></g><path d=\"M38 63q10 12 20 0Z\" fill=\"#5a1d1a\"></path><path d=\"M43 68q5 3 10 0-5 5-10 0Z\" fill=\"#e0736a\"></path><circle cx=\"32\" cy=\"62\" r=\"4.5\" fill=\"#e0736a\" opacity=\".55\"></circle><circle cx=\"64\" cy=\"62\" r=\"4.5\" fill=\"#e0736a\" opacity=\".55\"></circle><path class=\"f-spark\" d=\"M76 34l1.5 3.5 3.5 1.5-3.5 1.5L76 44l-1.5-3.5L71 39l3.5-1.5Z\" fill=\"#ffd27a\"></path></g>", "oops": "<g class=\"f-body\"><g class=\"f-ear f-l\"><path d=\"M26 52 3 40 23 63Z\" fill=\"#e2ac80\"></path><path d=\"M24 53 10 45 23 59Z\" fill=\"#c98660\"></path></g><g class=\"f-ear f-r\"><path d=\"M70 52 93 40 73 63Z\" fill=\"#e2ac80\"></path><path d=\"M72 53 86 45 73 59Z\" fill=\"#c98660\"></path></g><circle cx=\"48\" cy=\"56\" r=\"23\" fill=\"#eebd93\"></circle><path d=\"M30 74Q48 86 66 74l3 9Q48 95 27 83Z\" fill=\"#c8423b\"></path><path d=\"M60 80l10 2-2 12-9-3Z\" fill=\"#a8322d\"></path><g class=\"f-hat\"><path d=\"M22 47Q24 18 50 13 70 9 86 22 74 22 68 29 75 39 74 47Q48 36 22 47Z\" fill=\"#2c6a44\"></path><path d=\"M36 22Q52 14 68 29\" stroke=\"#245a3a\" stroke-width=\"3\" fill=\"none\"></path><circle class=\"f-pom\" cx=\"87\" cy=\"23\" r=\"5.5\" fill=\"#f6f9ff\"></circle></g><path d=\"M21 45Q48 34 75 45v6Q48 40 21 51Z\" fill=\"#d9a94f\"></path><g class=\"f-eyes\"><circle cx=\"39\" cy=\"54\" r=\"5.5\" fill=\"#fff\"></circle><circle cx=\"39\" cy=\"55.5\" r=\"2.4\" fill=\"#1b1a22\"></circle></g><path d=\"M53 51l8 3.5-8 3.5\" stroke=\"#1b1a22\" stroke-width=\"2.4\" fill=\"none\" stroke-linecap=\"round\" stroke-linejoin=\"round\"></path><path d=\"M33 46l9-3M54 45l9-1\" stroke=\"#6b4426\" stroke-width=\"2\" stroke-linecap=\"round\"></path><path d=\"M39 67q3-4 6 0t6 0 6 0\" stroke=\"#5a1d1a\" stroke-width=\"2.4\" fill=\"none\" stroke-linecap=\"round\"></path><path class=\"f-drop\" d=\"M73 38q4 6 0 9-4-3 0-9Z\" fill=\"#7fe0ff\"></path><circle cx=\"64\" cy=\"62\" r=\"4.5\" fill=\"#e0736a\" opacity=\".5\"></circle></g>"};
function frimm(e){
  return `<svg viewBox="0 0 100 100" role="img" aria-label="Frimm"><defs><clipPath id="fc${e}"><circle cx="50" cy="50" r="50"/></clipPath></defs><g clip-path="url(#fc${e})"><rect width="100" height="100" fill="#17161f"/><circle cx="50" cy="47" r="44" fill="#24222e"/><svg x="4" y="6" width="92" height="92" viewBox="-2 0 100 98">${FRIMM_SITE[e]}</svg></g></svg>`}

// Chimney: two textures, same drawing (from the prototype; 256x428 logical, drawn at 2x)
function drawChimney(cv,hot){
  const c=cv.getContext("2d");c.setTransform(2,0,0,2,0,0);c.clearRect(0,0,256,428);
  const R=rng(7);
  const bricks=(x0,y0,x1,y1)=>{c.save();c.beginPath();c.rect(x0,y0,x1-x0,y1-y0);c.clip();
    c.fillStyle=hot?"#ffb752":"#0b0a10";c.fillRect(x0,y0,x1-x0,y1-y0);
    const rh=13,bw=27;let row=0;
    for(let y=y0;y<y1;y+=rh,row++)for(let x=x0-(row%2?bw/2:0);x<x1;x+=bw){const l=R();
      c.fillStyle=hot?`hsl(${12+l*16},${80}%,${28+l*18}%)`:`hsl(${252+l*18},${8+l*6}%,${16+l*9}%)`;c.fillRect(x+1,y+1,bw-2,rh-2);
      c.fillStyle=hot?"rgba(255,226,160,.4)":"rgba(255,255,255,.07)";c.fillRect(x+1,y+1,bw-2,1.5);
      c.fillStyle="rgba(0,0,0,.28)";c.fillRect(x+1,y+rh-2.5,bw-2,1.5)}
    const g=c.createLinearGradient(x0,0,x1,0);g.addColorStop(0,"rgba(0,0,0,.5)");g.addColorStop(.22,"rgba(0,0,0,0)");g.addColorStop(.78,"rgba(0,0,0,0)");g.addColorStop(1,"rgba(0,0,0,.5)");c.fillStyle=g;c.fillRect(x0,y0,x1-x0,y1-y0);c.restore()};
  const slab=(x,y,w,h,a,b)=>{const g=c.createLinearGradient(0,y,0,y+h);g.addColorStop(0,a);g.addColorStop(1,b);c.fillStyle=g;c.fillRect(x,y,w,h);c.fillStyle="rgba(255,255,255,.12)";c.fillRect(x,y,w,1.5);c.fillStyle="rgba(0,0,0,.4)";c.fillRect(x,y+h-2,w,2)};
  bricks(82,80,174,226);bricks(22,246,234,404);
  slab(70,64,116,16,hot?"#c9703a":"#57516a",hot?"#8a3d1c":"#3a3547");
  slab(8,226,240,20,hot?"#7a3a1e":"#4a362c",hot?"#4a1f10":"#2a1f1a");
  slab(6,400,244,22,hot?"#b8602e":"#4b465c",hot?"#6d3014":"#2d2a3a");
  // boca
  const arch=()=>{c.beginPath();c.moveTo(72,400);c.lineTo(72,346);c.arc(128,346,56,Math.PI,0);c.lineTo(184,400);c.closePath()};
  arch();c.lineWidth=12;c.strokeStyle=hot?"#d9783a":"#5a5470";c.stroke();
  c.save();c.lineWidth=1.5;c.strokeStyle=hot?"#ffcf80":"#15131c";for(let a=0;a<=12;a++){const t=Math.PI+a*Math.PI/12;c.beginPath();c.moveTo(128+50*Math.cos(t),346+50*Math.sin(t));c.lineTo(128+62*Math.cos(t),346+62*Math.sin(t));c.stroke()}c.restore();
  arch();if(hot){const g=c.createRadialGradient(128,396,6,128,380,90);g.addColorStop(0,"#ffb04a");g.addColorStop(.45,"#8a2a0c");g.addColorStop(1,"#1c0805");c.fillStyle=g}else c.fillStyle="#06050a";c.fill();
  // lenha
  c.save();c.translate(128,392);[[-14,-0.16],[12,0.2]].forEach(([dx,rot])=>{c.save();c.translate(dx,0);c.rotate(rot);c.fillStyle=hot?"#3a1408":"#241a16";c.beginPath();c.roundRect(-30,-6,60,11,5);c.fill();c.fillStyle=hot?"#ff8a2a":"#3a2a22";c.beginPath();c.ellipse(29,-.5,3,5,0,0,7);c.fill();c.restore()});c.restore();
  if(!hot){c.fillStyle="#eef4fb";const snow=(x0,x1,y,h,seed)=>{const r=rng(seed);c.beginPath();c.moveTo(x0,y);for(let x=x0;x<=x1;x+=8)c.quadraticCurveTo(x+4,y-h*(.5+r()),x+8,y-r()*2);c.lineTo(x1,y+3);c.lineTo(x0,y+3);c.closePath();c.fill()};
    snow(68,188,66,9,3);snow(6,250,228,7,5);c.globalAlpha=.6;snow(6,40,402,5,9);snow(214,250,402,5,11);c.globalAlpha=1;
    c.fillStyle="rgba(150,180,220,.35)";c.fillRect(70,66,116,2);c.fillRect(8,228,240,2)}
}

// The veil-fx atlas (from the prototype, without its reading grid)
function buildAtlas(atlas) {
  const ax = atlas.getContext("2d");
  // fogo: 8 quadros em laço. Bolhas de calor somadas, depois uma rampa de cor em degraus.
  const N=8,S=128,t=document.createElement("canvas");t.width=t.height=S;const c=t.getContext("2d",{willReadFrequently:true});
  const R=rng(42),B=[];for(let i=0;i<54;i++)B.push({ph:R(),x:(R()+R()+R())/1.5-1,k:R()<.3?2:1,w:R()*6.28,s:.7+R()*.6});
  const ramp=v=>{ // v 0..1 -> [r,g,b,a]
    if(v<.1)return[0,0,0,0];const a=Math.min(1,(v-.1)/.1);
    if(v<.3)return[190+v*200,30+v*120,10,a*255*.9];if(v<.52)return[255,90+(v-.3)*380,18,255];if(v<.78)return[255,174+(v-.52)*230,40+(v-.52)*300,255];return[255,238,150+Math.min(1,(v-.78)*4)*90,255]};
  for(let f=0;f<N;f++){c.globalCompositeOperation="source-over";c.fillStyle="#000";c.fillRect(0,0,S,S);c.globalCompositeOperation="lighter";
    for(const b of B){const p=(f/N*b.k+b.ph)%1,ax0=Math.abs(b.x),H=104*(1-.55*ax0)*b.s;
      const y=118-Math.pow(p,.85)*H,x=64+b.x*30*Math.pow(1-p,.7)+Math.sin(6.283*(p*1.5)+b.w)*7*p,r=(1-p)*(21-8*ax0)+4,al=Math.pow(1-p,1.1)*.3;
      const g=c.createRadialGradient(x,y,0,x,y,r);g.addColorStop(0,`rgba(255,255,255,${al})`);g.addColorStop(1,"rgba(255,255,255,0)");c.fillStyle=g;c.fillRect(x-r,y-r,2*r,2*r)}
    const g=c.createRadialGradient(64,120,0,64,120,34);g.addColorStop(0,"rgba(255,255,255,.5)");g.addColorStop(1,"rgba(255,255,255,0)");c.fillStyle=g;c.fillRect(20,86,88,42);
    const im=c.getImageData(0,0,S,S),d=im.data;for(let i=0;i<d.length;i+=4){const q=ramp(d[i]/255);d[i]=q[0];d[i+1]=q[1];d[i+2]=q[2];d[i+3]=q[3]}
    ax.putImageData(im,(f%4)*S,(f>>2)*S)}
  // neve do sacudir: 4 quadros
  const r2=rng(5);const fl=[];for(let i=0;i<70;i++)fl.push([r2(),r2(),r2()]);
  for(let f=0;f<4;f++){ax.save();ax.translate(f*128,256);ax.beginPath();ax.arc(64,62,54,0,7);ax.clip();for(const[a,b,s]of fl){const ang=a*6.283+f*.9,rad=(18+b*40)*(.5+f*.17);ax.fillStyle=`rgba(255,255,255,${.5+s*.5})`;ax.beginPath();ax.arc(64+Math.cos(ang)*rad,66+Math.sin(ang)*rad*.8-f*4,.8+s*1.6,0,7);ax.fill()}ax.restore()}
  // peças
  const Y=384;let g;
  ax.save();ax.translate(64,Y+64);for(let i=0;i<15;i++){ax.rotate(6.283/15);const gr=ax.createLinearGradient(0,0,0,-62);gr.addColorStop(0,"rgba(255,255,255,.9)");gr.addColorStop(1,"rgba(255,255,255,0)");ax.fillStyle=gr;ax.beginPath();ax.moveTo(0,0);ax.lineTo(-5,-62);ax.lineTo(5,-62);ax.fill()}ax.restore();
  ax.strokeStyle="#fff";ax.lineWidth=5;ax.shadowColor="#fff";ax.shadowBlur=10;ax.beginPath();ax.arc(192,Y+64,48,0,7);ax.stroke();ax.shadowBlur=0;
  g=ax.createRadialGradient(320,Y+64,0,320,Y+64,62);g.addColorStop(0,"#fff");g.addColorStop(1,"rgba(255,255,255,0)");ax.fillStyle=g;ax.fillRect(256,Y,128,128);
  g=ax.createRadialGradient(416,Y+32,0,416,Y+32,30);g.addColorStop(0,"rgba(200,196,214,.7)");g.addColorStop(1,"rgba(200,196,214,0)");ax.fillStyle=g;ax.fillRect(384,Y,64,64);
  const star=(x,y,r)=>{ax.fillStyle="#fff";ax.beginPath();for(let i=0;i<8;i++){const a=i*Math.PI/4,rr=i%2?r*.28:r;ax.lineTo(x+Math.cos(a)*rr,y+Math.sin(a)*rr)}ax.fill()};star(464,Y+16,14);
  g=ax.createRadialGradient(496,Y+16,0,496,Y+16,10);g.addColorStop(0,"#fff3c4");g.addColorStop(.5,"#ff9a2e");g.addColorStop(1,"rgba(255,154,46,0)");ax.fillStyle=g;ax.fillRect(480,Y,32,32);
  ax.fillStyle="#fff";ax.beginPath();ax.arc(464,Y+48,6,0,7);ax.fill();
  g=ax.createLinearGradient(0,Y+34,0,Y+62);g.addColorStop(0,"#a87a2e");g.addColorStop(.45,"#f2cf7a");g.addColorStop(1,"#a87a2e");ax.fillStyle=g;ax.fillRect(482,Y+34,28,28);
  ax.save();ax.translate(384,Y+72);ax.scale(1.55,1.35);ax.fillStyle="#d9a94f";ax.strokeStyle="#8a6524";ax.lineWidth=2;const bp=new Path2D("M40 26C30 4 6 2 6 16s22 12 34 10zM40 26C50 4 74 2 74 16s-22 12-34 10z");ax.fill(bp);ax.stroke(bp);ax.restore();
}

// ---- Node side ------------------------------------------------------------------------------------------------

async function drawAll() {
  const out = {};
  // chimney: 2x canvas down to 256x428, bottom-aligned in 256x512
  for (const hot of [false, true]) {
    const cv = document.createElement("canvas");
    cv.width = 512; cv.height = 856;
    drawChimney(cv, hot);
    const f = document.createElement("canvas");
    f.width = 256; f.height = 512;
    const g = f.getContext("2d");
    g.imageSmoothingQuality = "high";
    g.drawImage(cv, 0, 84, 256, 428);
    out[hot ? "chimney-hot" : "chimney-cold"] = [256, 512, Array.from(g.getImageData(0, 0, 256, 512).data)];
  }
  const atlas = document.createElement("canvas");
  atlas.width = atlas.height = 512;
  buildAtlas(atlas);
  out["veil-fx"] = [512, 512, Array.from(atlas.getContext("2d").getImageData(0, 0, 512, 512).data)];
  // frimm: SVG -> 128 px cells (the faces are round, clipped by the SVG itself)
  const fr = document.createElement("canvas");
  fr.width = 512; fr.height = 128;
  const fg = fr.getContext("2d");
  fg.imageSmoothingQuality = "high";
  for (const [i, e] of ["rush", "happy", "oops"].entries()) {
    const svg = frimm(e).replace("<svg ", '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" ');
    const img = new Image();
    img.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg);
    await img.decode();
    fg.drawImage(img, i * 128, 0, 128, 128);
  }
  out.frimm = [512, 128, Array.from(fg.getImageData(0, 0, 512, 128).data)];
  return out;
}

// The gift box: one three.js scene, `open` lifts the lid off. Rendered at 512 and halved down to 256 and 128.
function drawBox(open, sizes) {
  const THREE = window.THREE;
  const cv = document.createElement("canvas");
  cv.width = cv.height = 512;
  const r = new THREE.WebGLRenderer({ canvas: cv, antialias: true, alpha: true, preserveDrawingBuffer: true, premultipliedAlpha: false });
  r.setClearColor(0x000000, 0);
  const scene = new THREE.Scene();
  const cam = new THREE.PerspectiveCamera(30, 1, 0.1, 50);
  cam.position.set(2.4, open ? 3.9 : 3.2, 8.2);
  cam.lookAt(0, open ? 1.0 : 0.85, 0);
  scene.add(new THREE.HemisphereLight(0xffffff, 0x8a7a9a, 1.15));
  const sun = new THREE.DirectionalLight(0xffffff, 0.85);
  sun.position.set(3, 6, 4);
  scene.add(sun);
  const paper = new THREE.MeshStandardMaterial({ color: 0xc0392f, roughness: 0.55, metalness: 0.05 });
  const paperDark = new THREE.MeshStandardMaterial({ color: 0x4a1612, roughness: 0.8, side: THREE.DoubleSide });
  const gold = new THREE.MeshStandardMaterial({ color: 0xf0c25a, roughness: 0.4, metalness: 0.15, emissive: 0x4a3510 });
  const W = 1.7, H = 1.2, LH = 0.34, LW = 1.84;
  const root = new THREE.Group();
  scene.add(root);
  const box = (w, h, d, m, x, y, z) => { const o = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), m); o.position.set(x, y, z); return o; };
  if (!open) root.add(box(W, H, W, paper, 0, H / 2, 0));
  else {
    const t = 0.06;
    root.add(box(W, t, W, paperDark, 0, t / 2, 0));
    for (const s of [-1, 1]) { root.add(box(W, H, t, paper, 0, H / 2, s * (W / 2 - t / 2))); root.add(box(t, H, W - 2 * t, paper, s * (W / 2 - t / 2), H / 2, 0)); }
  }
  // the ribbon around the body (both ways), slightly proud of the paper
  root.add(box(0.28, H + 0.01, W + 0.03, gold, 0, H / 2, 0));
  root.add(box(W + 0.03, H + 0.01, 0.28, gold, 0, H / 2, 0));
  // the lid
  const lid = new THREE.Group();
  lid.add(box(LW, LH, LW, paper, 0, 0, 0));
  lid.add(box(0.3, LH + 0.01, LW + 0.03, gold, 0, 0, 0));
  lid.add(box(LW + 0.03, LH + 0.01, 0.3, gold, 0, 0, 0));
  if (!open) {
    lid.position.set(0, H + LH / 2 - 0.04, 0);
    // bow: two loops, a knot, two tails
    const loop = (sx) => { const m = new THREE.Mesh(new THREE.TorusGeometry(0.3, 0.11, 16, 40), gold); m.scale.set(1.1, 1, 0.9); m.rotation.set(0.35, sx * 0.55, 0); m.position.set(sx * 0.34, LH / 2 + 0.28, 0.05); return m; };
    lid.add(loop(-1), loop(1));
    const knot = new THREE.Mesh(new THREE.SphereGeometry(0.16, 20, 16), gold); knot.position.set(0, LH / 2 + 0.11, 0); lid.add(knot);
    for (const s of [-1, 1]) { const tail = box(0.16, 0.03, 0.55, gold, s * 0.17, LH / 2 + 0.02, 0.4); tail.rotation.y = s * 0.45; lid.add(tail); }
    root.add(lid);
  } else {
    lid.position.set(1.2, 2.2, -0.5);
    lid.rotation.set(0.3, -0.5, -0.55);
    lid.scale.setScalar(0.8);
    root.add(lid);
    // a gentle warm glow from inside the open box
    const glow = new THREE.PointLight(0xffc66a, 1.1, 3);
    glow.position.set(0, 0.7, 0);
    scene.add(glow);
  }
  root.rotation.y = -0.55;
  r.render(scene, cam);
  const outs = {};
  for (const size of sizes) {
    let cur = cv, w = 512;
    while (w / 2 >= size) { const c = document.createElement("canvas"); c.width = c.height = w / 2; const g = c.getContext("2d"); g.imageSmoothingQuality = "high"; g.drawImage(cur, 0, 0, w / 2, w / 2); cur = c; w /= 2; }
    const c = document.createElement("canvas");
    c.width = c.height = size;
    const g = c.getContext("2d");
    g.imageSmoothingQuality = "high";
    g.drawImage(cur, 0, 0, size, size);
    outs[size] = Array.from(g.getImageData(0, 0, size, size).data);
  }
  return outs;
}

// tga() in render-globes.js is square-only; the atlas pieces are not.
function tgaWH(rgba, w, h) {
  const head = Buffer.alloc(18);
  head[2] = 2;
  head.writeUInt16LE(w, 12);
  head.writeUInt16LE(h, 14);
  head[16] = 32;
  head[17] = 0x28;
  const body = Buffer.alloc(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    body[i * 4] = rgba[i * 4 + 2];
    body[i * 4 + 1] = rgba[i * 4 + 1];
    body[i * 4 + 2] = rgba[i * 4];
    body[i * 4 + 3] = rgba[i * 4 + 3];
  }
  return Buffer.concat([head, body]);
}

(async () => {
  const out = path.resolve(process.argv[2] || path.join(__dirname, "..", "Media", "Veil"));
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch({ args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"] });
  const page = await browser.newPage({ viewport: { width: 800, height: 800 }, deviceScaleFactor: 1 });
  await page.setContent('<!doctype html><meta charset="utf-8"><body style="margin:0"><script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>', { waitUntil: "networkidle" });
  await page.evaluate(`window.FRIMM_SITE=${JSON.stringify(FRIMM_SITE)};window.rng=${rng.toString()};window.frimm=${frimm.toString()};window.drawChimney=${drawChimney.toString()};window.buildAtlas=${buildAtlas.toString()};window.drawAll=${drawAll.toString()};window.drawBox=${drawBox.toString()};`);
  const flat = await page.evaluate("drawAll()");
  let n = 0;
  for (const [name, [w, h, data]] of Object.entries(flat)) { fs.writeFileSync(path.join(out, name + ".tga"), tgaWH(Buffer.from(data), w, h)); n++; }
  for (const open of [false, true]) {
    const bufs = await page.evaluate(`drawBox(${open}, [128, 256])`);
    const base = open ? "giftbox-open" : "giftbox";
    fs.writeFileSync(path.join(out, base + ".tga"), tga(Buffer.from(bufs[128]), 128));
    fs.writeFileSync(path.join(out, base + "-256.tga"), tga(Buffer.from(bufs[256]), 256));
    n += 2;
  }
  await browser.close();
  console.log(`${n} files in ${out}`);
})().catch((e) => { console.error(e); process.exit(1); });
