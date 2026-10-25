// AgentSweep 30-second intro film.
// Rendering contract (huashu-art-motion render.py): window.prepare(t) loads what frame t needs,
// window.renderFrame(t) draws it deterministically onto window.__canvas.
'use strict';

const QS = new URLSearchParams(location.search);
const W = +QS.get('w') || 1920, H = +QS.get('h') || 1080, TOTAL = 30;
const V = H > W;   // vertical cut: same timeline and events, every shot recomposed for 9:16
const C = {
  bg: '#0B0F1A', deep: '#05070D', panel: '#141B2D', raise: '#1C2438', well: '#0F1525',
  line: 'rgba(170,190,255,0.14)', fg: '#E6EBF7', muted: '#8892AC', dim: '#5A6380',
  ice: '#8FD8FF', green: '#4ADE80', yellow: '#FACC15', orange: '#FB923C', red: '#F87171',
};
const FONT = '"PingFang SC","Hiragino Sans GB",system-ui,sans-serif';
const MONO = '"SF Mono",Menlo,monospace';

const cv = document.getElementById('c');
cv.width = W;
cv.height = H;
const ctx = cv.getContext('2d');
window.__canvas = cv;
window.__total = TOTAL;

// ---------------------------------------------------------------- math

const clamp = (x, a = 0, b = 1) => Math.max(a, Math.min(b, x));
const lerp = (a, b, t) => a + (b - a) * t;
const prog = (t, start, dur) => clamp((t - start) / dur);
const sineIO = (x) => -(Math.cos(Math.PI * x) - 1) / 2;
const outCubic = (x) => 1 - Math.pow(1 - x, 3);
const outQuint = (x) => 1 - Math.pow(1 - x, 5);
const outBack = (x, s = 1.70158) => 1 + (s + 1) * Math.pow(x - 1, 3) + s * Math.pow(x - 1, 2);

/** Camera slam: 1.55 → 0.94 → 1.0 over 0.17 s. */
function slam(t, t0) {
  const p = (t - t0) / 0.17;
  if (p < 0) return 0;
  if (p >= 1) return 1;
  return p < 0.6 ? lerp(1.55, 0.94, outCubic(p / 0.6)) : lerp(0.94, 1, sineIO((p - 0.6) / 0.4));
}

/** Cut impact: the new shot lands at 1.03 and settles to 1.0 over 20 frames. */
const impact = (t, cut) => 1 + 0.03 * (1 - outCubic(prog(t, cut, 0.66)));

function seeded(seed) {
  let s = seed >>> 0;
  return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
}

// ---------------------------------------------------------------- drawing helpers

function rr(x, y, w, h, r) {
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, r);
}

function text(str, x, y, { size = 24, weight = 500, color = C.fg, align = 'left', font = FONT, alpha = 1, base = 'alphabetic' } = {}) {
  ctx.save();
  ctx.globalAlpha *= alpha;
  ctx.font = `${weight} ${size}px ${font}`;
  ctx.fillStyle = color;
  ctx.textAlign = align;
  ctx.textBaseline = base;
  ctx.fillText(str, x, y);
  ctx.restore();
}

/** Places world coordinates: focus point lands on screen center, scaled by zoom. */
function camera(fx, fy, zoom, sx = 0, sy = 0) {
  ctx.setTransform(zoom, 0, 0, zoom, W / 2 - fx * zoom + sx, H / 2 - fy * zoom + sy);
}

function screen() { ctx.setTransform(1, 0, 0, 1, 0, 0); }

function backdrop() {
  screen();
  ctx.fillStyle = C.bg;
  ctx.fillRect(0, 0, W, H);
  let g = ctx.createRadialGradient(W * 0.55, -H * 0.15, 0, W * 0.55, -H * 0.15, H * 1.1);
  g.addColorStop(0, 'rgba(91,168,255,0.16)');
  g.addColorStop(1, 'rgba(91,168,255,0)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, W, H);
  g = ctx.createRadialGradient(W / 2, H / 2, H * 0.35, W / 2, H / 2, H * 1.0);
  g.addColorStop(0, 'rgba(0,0,0,0)');
  g.addColorStop(1, 'rgba(0,0,0,0.55)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, W, H);
}

/** Faint dot grid in world space, so every camera move reads against the ground. */
function worldGrid(x0, y0, x1, y1) {
  ctx.fillStyle = 'rgba(143,216,255,0.07)';
  for (let x = Math.floor(x0 / 48) * 48; x < x1; x += 48)
    for (let y = Math.floor(y0 / 48) * 48; y < y1; y += 48) ctx.fillRect(x - 1.5, y - 1.5, 3, 3);
}

/** Lower-left caption in screen space. */
function caption(str, t, t0) {
  const p = outCubic(prog(t, t0, 0.35));
  if (p <= 0) return;
  screen();
  ctx.save();
  ctx.globalAlpha = p;
  const band = V ? 520 : 380;
  const scrim = ctx.createLinearGradient(0, H - band, 0, H);
  scrim.addColorStop(0, 'rgba(5,7,13,0)');
  scrim.addColorStop(0.45, 'rgba(5,7,13,0.82)');
  scrim.addColorStop(1, 'rgba(5,7,13,0.97)');
  ctx.fillStyle = scrim;
  ctx.fillRect(0, H - band, W, band);
  const x = V ? 84 : 120, size = V ? 72 : 56;
  const y = (V ? 1760 : 958) + (1 - p) * 22;
  ctx.fillStyle = C.ice;
  rr(x, y - size * 0.9, 7, size * 1.04, 3);
  ctx.fill();
  ctx.shadowColor = 'rgba(0,0,0,0.6)';
  ctx.shadowBlur = 24;
  text(str, x + 30, y, { size, weight: 600 });
  ctx.restore();
}

function cursorArrow(x, y, s = 1) {
  ctx.save();
  ctx.translate(x, y);
  ctx.scale(s * 1.6, s * 1.6);
  ctx.beginPath();
  ctx.moveTo(0, 0); ctx.lineTo(0, 22); ctx.lineTo(5.5, 17); ctx.lineTo(9.5, 26); ctx.lineTo(13, 24.5);
  ctx.lineTo(9, 15.8); ctx.lineTo(16, 15.8); ctx.closePath();
  ctx.fillStyle = '#fff';
  ctx.strokeStyle = '#000';
  ctx.lineWidth = 1.4;
  ctx.shadowColor = 'rgba(0,0,0,0.5)';
  ctx.shadowBlur = 6;
  ctx.fill();
  ctx.shadowBlur = 0;
  ctx.stroke();
  ctx.restore();
}

function folder(x, y, w, tint, { glyph = '', alpha = 1, scale = 1 } = {}) {
  const h = w * 0.76;
  ctx.save();
  ctx.globalAlpha *= alpha;
  ctx.translate(x, y);
  ctx.scale(scale, scale);
  ctx.translate(-w / 2, -h / 2);
  ctx.fillStyle = '#273352';
  rr(0, 0, w * 0.44, h * 0.3, 10);
  ctx.fill();
  const g = ctx.createLinearGradient(0, h * 0.14, 0, h);
  g.addColorStop(0, '#34426A');
  g.addColorStop(1, '#222D4A');
  ctx.fillStyle = g;
  rr(0, h * 0.14, w, h * 0.86, 14);
  ctx.fill();
  ctx.strokeStyle = 'rgba(143,216,255,0.35)';
  ctx.lineWidth = 2;
  ctx.stroke();
  ctx.fillStyle = tint;
  rr(w * 0.08, h * 0.3, w * 0.84, 10, 5);
  ctx.fill();
  if (glyph) text(glyph, w / 2, h * 0.72, { size: w * 0.3, weight: 600, color: C.ice, align: 'center', base: 'middle' });
  ctx.restore();
}

// ---------------------------------------------------------------- assets

const icon = new Image();
icon.src = 'assets/icon.png';

const FOOT_T0 = 1.3, FOOT_N = 450, FOOT_W = 2016, FOOT_H = 1312;   // layout space; vertical loads the full-res set
const FOOT_DIR = V ? 'footage_v' : 'footage';
const frames = new Map();

function footIndex(ft) { return clamp(Math.round((ft - FOOT_T0) * 30) + 1, 1, FOOT_N); }

async function loadFrame(i) {
  if (frames.has(i)) return frames.get(i);
  const img = new Image();
  img.src = `${FOOT_DIR}/f${String(i).padStart(4, '0')}.jpg`;
  await img.decode();
  frames.set(i, img);
  for (const k of frames.keys()) if (Math.abs(k - i) > 6) frames.delete(k);
  return img;
}

/** Recording time shown at film time t, or null when the shot is code-drawn. */
function footageTime(t) {
  if (t >= 8 && t < 13) return 1.6 + (t - 8) * 1.26;           // scan, slightly sped up
  if (t >= 13 && t < 18) return 8.0 + Math.min(t - 13, 2.8);    // ring grows, then holds
  if (t >= 18 && t < 22) return 10.9 + (t - 18);                // black hole
  return null;
}

// Window placement in world space.
const WIN_K = 0.7, WIN_W = FOOT_W * WIN_K, WIN_H = FOOT_H * WIN_K;
const WIN_X = 960 - WIN_W / 2, WIN_Y = 540 - WIN_H / 2;
const fw = (px, py) => [WIN_X + px * WIN_K, WIN_Y + py * WIN_K];   // footage pixel → world
const RING = fw(799, 544);

function footageWindow(img) {
  ctx.save();
  ctx.shadowColor = 'rgba(0,0,0,0.65)';
  ctx.shadowBlur = 80;
  ctx.shadowOffsetY = 30;
  ctx.fillStyle = C.deep;
  rr(WIN_X, WIN_Y, WIN_W, WIN_H, 16);
  ctx.fill();
  ctx.restore();
  ctx.save();
  rr(WIN_X, WIN_Y, WIN_W, WIN_H, 16);
  ctx.clip();
  ctx.drawImage(img, WIN_X, WIN_Y, WIN_W, WIN_H);
  ctx.restore();
  ctx.strokeStyle = 'rgba(170,190,255,0.18)';
  ctx.lineWidth = 1.5;
  rr(WIN_X, WIN_Y, WIN_W, WIN_H, 16);
  ctx.stroke();
}

// ---------------------------------------------------------------- shot 1 & 6: free-space meter

const DISK = 494.38, FREE0 = 24.4;
const BLOCKS = [
  ['开发缓存', 2.14, '#94A3B8'], ['Codex', 8.39, '#10A37F'], ['Cursor', 5.79, '#8B8BFF'], ['ZCode', 1.79, '#22D3EE'],
  ['Kimi Code', 1.53, '#CBD5E1'], ['opencode', 1.47, '#F5A524'], ['其他', 1.0, '#5A6380'],
];
const AGENT = BLOCKS.reduce((s, b) => s + b[1], 0);   // 22.1 GB, the scan total
const FREED = 8.37;                                    // the selection the clean moves to the Trash
const BAR = { x: 380, y: 470, w: 1160, h: 64 };

/** grow[i] in 0..1 is how far block i has filled in; keep is the share left after the clean. */
function meter(t, grow, keep, { alert = 0 } = {}) {
  const used = BLOCKS.reduce((s, b, i) => s + b[1] * grow[i] * keep, 0);
  const free = FREE0 - used;
  const low = free < 5;

  // card
  ctx.save();
  ctx.shadowColor = 'rgba(0,0,0,0.55)';
  ctx.shadowBlur = 60;
  ctx.shadowOffsetY = 24;
  ctx.fillStyle = C.panel;
  rr(320, 300, 1280, 420, 28);
  ctx.fill();
  ctx.restore();
  ctx.strokeStyle = C.line;
  ctx.lineWidth = 1.5;
  rr(320, 300, 1280, 420, 28);
  ctx.stroke();

  // drive glyph + name
  ctx.fillStyle = '#273250';
  rr(380, 352, 74, 54, 10);
  ctx.fill();
  ctx.fillStyle = C.ice;
  ctx.beginPath(); ctx.arc(436, 392, 4, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = 'rgba(143,216,255,0.35)';
  rr(392, 362, 50, 4, 2); ctx.fill();
  text('Macintosh HD', 480, 384, { size: 38, weight: 600 });
  text(`${DISK} GB · 剩余空间`, 482, 420, { size: 22, color: C.muted });

  // readout
  const col = low ? C.red : free > 9 ? C.green : C.fg;
  ctx.font = `300 64px ${MONO}`;
  const numW = ctx.measureText(free.toFixed(1)).width;
  text('可用', 1494 - numW - 14, 410, { size: 26, color: C.muted, align: 'right' });
  text(free.toFixed(1), 1494, 414, { size: 64, weight: 300, color: col, align: 'right', font: MONO });
  text('GB', 1540, 414, { size: 26, color: C.muted, align: 'right' });

  // bar well with moving stripes for the empty part
  ctx.save();
  rr(BAR.x, BAR.y, BAR.w, BAR.h, 14);
  ctx.clip();
  ctx.fillStyle = C.well;
  ctx.fillRect(BAR.x, BAR.y, BAR.w, BAR.h);
  ctx.strokeStyle = low ? 'rgba(248,113,113,0.28)' : free > 9 ? 'rgba(74,222,128,0.22)' : 'rgba(143,216,255,0.12)';
  ctx.lineWidth = 6;
  const shift = (t * 40) % 24;
  for (let x = BAR.x - 80 + shift; x < BAR.x + BAR.w + 80; x += 24) {
    ctx.beginPath(); ctx.moveTo(x, BAR.y + BAR.h); ctx.lineTo(x + 40, BAR.y); ctx.stroke();
  }
  let x = BAR.x;
  BLOCKS.forEach((b, i) => {
    const w = (b[1] * grow[i] * keep / FREE0) * BAR.w;
    if (w > 0.5) {
      ctx.fillStyle = b[2];
      ctx.fillRect(x, BAR.y, Math.max(0, w - 3), BAR.h);
      ctx.fillStyle = 'rgba(255,255,255,0.12)';
      ctx.fillRect(x, BAR.y, Math.max(0, w - 3), 6);
    }
    x += w;
  });
  ctx.restore();
  ctx.strokeStyle = low ? `rgba(248,113,113,${0.55 + 0.35 * Math.sin(t * 9) ** 2})` : C.line;
  ctx.lineWidth = low ? 3 : 1.5;
  rr(BAR.x, BAR.y, BAR.w, BAR.h, 14);
  ctx.stroke();

  // labels under the three biggest blocks and one for the rest
  let lx = BAR.x;
  const spans = BLOCKS.map((b, i) => {
    const w = (b[1] * grow[i] * keep / FREE0) * BAR.w;
    const s = { x: lx, w, g: grow[i] };
    lx += w;
    return s;
  });
  // two rows so narrow blocks never collide: the small first block hangs on the lower row
  const label = (name, gb, sx, g, color, row) => {
    if (g < 0.3) return;
    const a = prog(g, 0.3, 0.5);
    const y = 588 + row * 64;
    ctx.fillStyle = color;
    ctx.globalAlpha = a;
    rr(sx, 548, 4, y - 548 + 32, 2); ctx.fill();
    ctx.globalAlpha = 1;
    text(name, sx + 16, y, { size: 24, weight: 600, alpha: a });
    text(`${(gb * keep).toFixed(gb * keep >= 10 ? 1 : 2)} GB`, sx + 16, y + 30, { size: 22, color: C.muted, font: MONO, alpha: a });
  };
  label('开发缓存', BLOCKS[0][1], spans[0].x, spans[0].g, BLOCKS[0][2], 1);
  label('Codex', BLOCKS[1][1], spans[1].x, spans[1].g, BLOCKS[1][2], 0);
  label('Cursor', BLOCKS[2][1], spans[2].x, spans[2].g, BLOCKS[2][2], 1);
  const rest = BLOCKS.slice(3).reduce((s, b) => s + b[1], 0);
  label('ZCode、Kimi 等', rest, spans[3].x, spans[6].g, BLOCKS[3][2], 0);
  return free;
}

function alertSheet(t, t0) {
  const s = slam(t, t0);
  if (!s) return;
  ctx.save();
  ctx.fillStyle = `rgba(3,5,10,${0.45 * prog(t, t0, 0.15)})`;
  ctx.fillRect(-400, -400, W + 800, H + 800);
  ctx.translate(960, 590);
  ctx.scale(s, s);
  ctx.shadowColor = 'rgba(0,0,0,0.7)';
  ctx.shadowBlur = 70;
  ctx.shadowOffsetY = 28;
  ctx.fillStyle = '#262D40';
  rr(-300, -150, 600, 300, 24);
  ctx.fill();
  ctx.shadowBlur = 0;
  ctx.shadowOffsetY = 0;
  ctx.strokeStyle = 'rgba(255,255,255,0.12)';
  ctx.lineWidth = 1.5;
  ctx.stroke();
  // warning glyph
  ctx.fillStyle = C.yellow;
  ctx.beginPath(); ctx.moveTo(0, -122); ctx.lineTo(34, -64); ctx.lineTo(-34, -64); ctx.closePath(); ctx.fill();
  text('!', 0, -71, { size: 36, weight: 800, color: '#1B1405', align: 'center' });
  text('启动磁盘几乎已满', 0, -18, { size: 32, weight: 600, align: 'center' });
  text('这台 Mac 只剩 2.3 GB 可用空间。', 0, 22, { size: 22, color: C.muted, align: 'center' });
  ctx.fillStyle = '#3A4258';
  rr(-260, 64, 250, 52, 12); ctx.fill();
  text('以后', -135, 98, { size: 22, weight: 600, align: 'center' });
  ctx.fillStyle = '#4C8DF0';
  rr(10, 64, 250, 52, 12); ctx.fill();
  text('管理…', 135, 98, { size: 22, weight: 600, align: 'center' });
  ctx.restore();
}

const DROP = BLOCKS.map((_, i) => 0.3 + i * 0.32);   // when each block starts to fall
const FALL = 0.28;

function shot1(t) {
  // the alert shakes the frame hard; every landing block gives it a small knock
  const alertShake = t >= 3.0 ? Math.max(0, 1 - (t - 3.0) / 0.3) : 0;
  const knock = DROP.reduce((k, d) => k + Math.max(0, 1 - Math.abs(t - d - FALL) / 0.08) * (t >= d + FALL ? 1 : 0), 0);
  // follow the filling front along the bar, then pull out to the whole card as it turns red
  const centers = [];
  let acc = BAR.x;
  for (const blk of BLOCKS) { const w = (blk[1] / FREE0) * BAR.w; centers.push(acc + w / 2); acc += w; }
  let i = 0;
  while (i < BLOCKS.length - 1 && t >= DROP[i + 1]) i++;
  const from = i === 0 ? centers[0] - 120 : centers[i - 1];
  const followX = lerp(from, centers[i], sineIO(prog(t, DROP[i], 0.3)));
  const out = outQuint(prog(t, 2.55, 0.5));
  const fx = lerp(followX + 120, 960, out), fy = lerp(BAR.y - 10, 510, out);
  camera(fx, fy, lerp(2.0, 1.24, out) * impact(t, 0),
    Math.sin(t * 90) * 9 * alertShake, Math.cos(t * 77) * 6 * alertShake + knock * 5);
  worldGrid(-200, -200, 2200, 1300);
  meter(t, DROP.map((d) => (t >= d + FALL ? 1 : 0)), 1);
  // blocks falling into the bar
  let x = BAR.x;
  BLOCKS.forEach((b, i) => {
    const w = (b[1] / FREE0) * BAR.w;
    const p = prog(t, DROP[i], FALL);
    if (p > 0 && p < 1) {
      const y = BAR.y - 360 * (1 - p * p);
      ctx.fillStyle = b[2];
      rr(x, y, Math.max(4, w - 3), BAR.h, 10);
      ctx.fill();
      ctx.fillStyle = 'rgba(255,255,255,0.14)';
      rr(x, y, Math.max(4, w - 3), 8, 4);
      ctx.fill();
    }
    x += w;
  });
  alertSheet(t, 3.0);
}

// ---------------------------------------------------------------- shot 2: hidden folders

const FOLDERS = [
  ['.codex', '8.39 GB', '#10A37F'], ['.cursor', '5.79 GB', '#8B8BFF'], ['.cache/uv', '1.19 GB', '#94A3B8'],
  ['.zcode', '1.79 GB', '#22D3EE'], ['.kimi-code', '1.53 GB', '#CBD5E1'], ['…/opencode', '1.47 GB', '#F5A524'],
  ['.minimax', '700 MB', '#F43F5E'], ['.claude', '262 MB', '#D97757'],
];
const FX = (i) => 300 + i * 440;

function shot2(t) {
  const lt = t - 4;
  // hold → glide → hold → glide → hold
  const fx = lt < 1.2 ? 800
    : lt < 1.9 ? lerp(800, 1840, sineIO(prog(lt, 1.2, 0.7)))
      : lt < 2.6 ? 1840
        : lerp(1840, 2840, sineIO(prog(lt, 2.6, 0.7)));
  camera(fx, 540, impact(t, 4));
  worldGrid(-400, -200, 3600, 1300);
  text('~  主目录 · 隐藏文件夹', 100, 290, { size: 30, color: C.muted, font: MONO });
  ctx.strokeStyle = C.line;
  ctx.lineWidth = 1.5;
  ctx.beginPath(); ctx.moveTo(100, 318); ctx.lineTo(3600, 318); ctx.stroke();

  FOLDERS.forEach(([name, size, tint], i) => {
    const x = FX(i);
    // each folder pops when the camera first reaches it
    const enter = x < 1760 ? 0.05 + i * 0.16 : x < 2800 ? 1.45 + (i - 4) * 0.16 : 2.85 + (i - 6) * 0.16;
    const p = prog(lt, enter, 0.32);
    if (p <= 0) return;
    const sc = lerp(0.6, 1, outBack(p));
    const bob = Math.sin((t + i * 0.7) * 2.2) * 4 - 260 * (1 - outCubic(p));
    folder(x, 510 + bob, 240, tint, { scale: sc, alpha: Math.min(1, p * 2) });
    text(name, x, 700, { size: 34, weight: 600, font: MONO, align: 'center', alpha: p });
    text(size, x, 744, { size: 28, color: C.muted, font: MONO, align: 'center', alpha: p });
    // question badge
    const q = prog(lt, enter + 0.4, 0.28);
    if (q > 0) {
      ctx.save();
      ctx.translate(x + 104, 412 + bob);
      ctx.scale(outBack(q, 2.4), outBack(q, 2.4));
      ctx.fillStyle = C.orange;
      ctx.beginPath(); ctx.arc(0, 0, 32, 0, Math.PI * 2); ctx.fill();
      text('?', 0, 14, { size: 42, weight: 800, color: '#1B1405', align: 'center' });
      ctx.restore();
    }
  });
  caption('哪些能删？', t, 4.5);
}

// ---------------------------------------------------------------- shots 3–5: the app

function shot3(t, img) {
  // pull out from the counter to the whole window
  const p = sineIO(prog(t, 8.15, 1.15));
  const z = lerp(2.05, 1.0, p) * impact(t, 8);
  camera(lerp(RING[0], 960, p), lerp(RING[1], 540, p), z);
  worldGrid(-400, -300, 2400, 1400);
  footageWindow(img);
  caption('认识 14 种工具', t, 9.4);
}

const CALLOUTS = [
  { at: fw(842, 302), to: [1010, 214], label: '可安全删除', color: C.green, t0: 15.3 },
  { at: fw(1043, 443), to: [1196, 372], label: '旧会话', color: C.yellow, t0: 15.8 },
  { at: fw(559, 474), to: [452, 330], label: '受保护', color: C.red, t0: 16.3 },
];

function callout(t, c) {
  const p = prog(t, c.t0, 0.28);
  if (p <= 0) return;
  const [ax, ay] = c.at, [lx, ly] = c.to;
  const ex = lerp(ax, lx, outCubic(p)), ey = lerp(ay, ly, outCubic(p));
  ctx.strokeStyle = c.color;
  ctx.lineWidth = 2.5;
  ctx.beginPath(); ctx.moveTo(ax, ay); ctx.lineTo(ex, ey); ctx.stroke();
  ctx.fillStyle = c.color;
  ctx.beginPath(); ctx.arc(ax, ay, 7, 0, Math.PI * 2); ctx.fill();
  ctx.strokeStyle = 'rgba(255,255,255,0.8)';
  ctx.lineWidth = 2;
  ctx.beginPath(); ctx.arc(ax, ay, 7 + 10 * prog(t, c.t0, 0.5), 0, Math.PI * 2);
  ctx.globalAlpha = 1 - prog(t, c.t0, 0.5);
  ctx.stroke();
  ctx.globalAlpha = 1;
  const q = prog(t, c.t0 + 0.2, 0.25);
  if (q <= 0) return;
  ctx.save();
  ctx.translate(lx, ly);
  ctx.scale(outBack(q), outBack(q));
  ctx.font = `600 30px ${FONT}`;
  const w = ctx.measureText(c.label).width + 40;
  const left = c.side ? c.side === 'left' : lx < ax;
  const bx = left ? -w : 0;
  ctx.fillStyle = 'rgba(11,15,26,0.92)';
  rr(bx, -26, w, 52, 26); ctx.fill();
  ctx.strokeStyle = c.color;
  ctx.lineWidth = 2;
  ctx.stroke();
  text(c.label, bx + w / 2, 10, { size: 30, weight: 600, color: c.color, align: 'center' });
  ctx.restore();
}

function shot4(t, img) {
  const p = sineIO(prog(t, 14.0, 1.2));
  camera(lerp(960, 900, p), lerp(540, 470, p), lerp(1.0, 1.32, p) * impact(t, 13));
  worldGrid(-400, -300, 2400, 1400);
  footageWindow(img);
  for (const c of CALLOUTS) callout(t, c);
  caption('每一项写清楚', t, 13.4);
}

function shot5(t, img) {
  // the hole opens: one fast push, then hold on it
  const p = outCubic(prog(t, 18.25, 0.3));
  const z = lerp(1.18, 1.62, p);
  camera(RING[0], RING[1], z);
  worldGrid(-400, -300, 2400, 1400);
  footageWindow(img);
  caption('移到废纸篓', t, 18.6);
}

// ---------------------------------------------------------------- shot 6: empty the Trash

const DOCK = { x: 560, y: 850, w: 800, h: 124 };
const TRASH = [DOCK.x + DOCK.w - 74, DOCK.y + DOCK.h / 2];

function trashCan(x, y, full, lid) {
  ctx.save();
  ctx.translate(x, y);
  ctx.fillStyle = 'rgba(230,235,247,0.12)';
  ctx.strokeStyle = 'rgba(230,235,247,0.85)';
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.moveTo(-32, -26); ctx.lineTo(-26, 40); ctx.lineTo(26, 40); ctx.lineTo(32, -26); ctx.closePath();
  ctx.fill(); ctx.stroke();
  for (const dx of [-14, 0, 14]) { ctx.beginPath(); ctx.moveTo(dx, -14); ctx.lineTo(dx * 0.85, 30); ctx.stroke(); }
  if (full > 0) {
    ctx.globalAlpha = full;
    const r = seeded(11);
    for (let i = 0; i < 6; i++) {
      ctx.fillStyle = ['#E6EBF7', '#C9D3EA', '#8FD8FF'][i % 3];
      ctx.beginPath(); ctx.arc(-20 + r() * 40, -30 - r() * 12, 9 + r() * 5, 0, Math.PI * 2); ctx.fill();
    }
    ctx.globalAlpha = 1;
  }
  ctx.save();
  ctx.translate(-36, -30);
  ctx.rotate(-lid);
  ctx.fillStyle = 'rgba(230,235,247,0.85)';
  rr(0, -6, 72, 8, 3); ctx.fill();
  ctx.restore();
  ctx.restore();
}

function dock(t, full, lid) {
  ctx.save();
  ctx.fillStyle = 'rgba(28,36,56,0.88)';
  ctx.shadowColor = 'rgba(0,0,0,0.5)';
  ctx.shadowBlur = 40;
  rr(DOCK.x, DOCK.y, DOCK.w, DOCK.h, 32);
  ctx.fill();
  ctx.restore();
  ctx.strokeStyle = 'rgba(255,255,255,0.12)';
  ctx.lineWidth = 1.5;
  rr(DOCK.x, DOCK.y, DOCK.w, DOCK.h, 32);
  ctx.stroke();
  const tiles = ['#3A4D7A', '#10A37F', '#8B8BFF', '#22D3EE', '#D97757'];
  tiles.forEach((c, i) => {
    const x = DOCK.x + 30 + i * 112;
    ctx.fillStyle = c;
    rr(x, DOCK.y + 18, 88, 88, 22);
    ctx.fill();
    ctx.fillStyle = 'rgba(255,255,255,0.18)';
    rr(x, DOCK.y + 18, 88, 30, 22);
    ctx.fill();
  });
  ctx.drawImage(icon, DOCK.x + 30 + 5 * 112 - 6, DOCK.y + 12, 100, 100);
  ctx.fillStyle = 'rgba(255,255,255,0.18)';
  ctx.fillRect(DOCK.x + DOCK.w - 150, DOCK.y + 24, 2, 76);
  trashCan(TRASH[0], TRASH[1] + 4, full, lid);
}

function shot6(t) {
  const lt = t - 22;
  const pull = outQuint(prog(lt, 1.0, 1.3));
  camera(lerp(TRASH[0] - 80, 960, pull), lerp(TRASH[1] - 110, 590, pull), lerp(1.75, 1.08, pull) * impact(t, 22));
  worldGrid(-400, -300, 2400, 1500);

  // the clean frees FREED GB spread over the tool blocks
  const shrink = outCubic(prog(lt, 1.35, 1.1));
  const keep = 1 - shrink * (FREED / AGENT);
  const free = meter(t, BLOCKS.map(() => 1), keep);
  if (shrink > 0) {
    const fx = BAR.x + ((FREE0 - free) / FREE0) * BAR.w;
    text(`+${(free - (FREE0 - AGENT)).toFixed(1)} GB`, (fx + BAR.x + BAR.w) / 2, BAR.y + 44, { size: 30, weight: 700, color: C.green, align: 'center', font: MONO, alpha: shrink });
  }

  // Trash: menu, click, papers fly out
  const empty = prog(lt, 0.8, 0.01);
  const lid = Math.sin(prog(lt, 0.8, 0.5) * Math.PI) * 0.6;
  dock(t, 1 - empty, lid);
  const menu = prog(lt, 0.3, 0.15) * (1 - prog(lt, 0.85, 0.1));
  if (menu > 0) {
    ctx.save();
    ctx.globalAlpha = menu;
    ctx.fillStyle = '#2B3247';
    rr(TRASH[0] - 110, TRASH[1] - 150, 220, 58, 12);
    ctx.fill();
    ctx.strokeStyle = 'rgba(255,255,255,0.14)';
    ctx.stroke();
    const hot = prog(lt, 0.62, 0.05);
    if (hot > 0) { ctx.fillStyle = '#4C8DF0'; rr(TRASH[0] - 104, TRASH[1] - 144, 208, 46, 9); ctx.fill(); }
    text('清空废纸篓', TRASH[0], TRASH[1] - 112, { size: 24, weight: 600, align: 'center' });
    ctx.restore();
  }
  if (lt >= 0.8) {
    const r = seeded(5);
    for (let i = 0; i < 14; i++) {
      const a = -Math.PI / 2 + (r() - 0.5) * 1.6, sp = 160 + r() * 260, k = prog(lt, 0.8 + r() * 0.08, 0.7);
      if (k <= 0 || k >= 1) continue;
      ctx.globalAlpha = 1 - k;
      ctx.fillStyle = ['#E6EBF7', '#C9D3EA', '#8FD8FF'][i % 3];
      const px = TRASH[0] + Math.cos(a) * sp * k, py = TRASH[1] - 30 + Math.sin(a) * sp * k + 220 * k * k;
      ctx.beginPath(); ctx.arc(px, py, 8 * (1 - k * 0.5), 0, Math.PI * 2); ctx.fill();
    }
    ctx.globalAlpha = 1;
  }
  // pointer: comes to the Trash, opens the menu, clicks the item
  const cx = lt < 0.3 ? lerp(TRASH[0] - 160, TRASH[0] + 8, sineIO(prog(lt, 0, 0.3))) : TRASH[0] + 8;
  const cy = lt < 0.3 ? lerp(TRASH[1] + 60, TRASH[1] - 6, sineIO(prog(lt, 0, 0.3)))
    : lerp(TRASH[1] - 6, TRASH[1] - 128, sineIO(prog(lt, 0.4, 0.22)));
  const press = (lt > 0.25 && lt < 0.33) || (lt > 0.7 && lt < 0.78) ? 0.88 : 1;
  cursorArrow(cx, cy, press * (1 - prog(lt, 1.2, 0.3)));
  caption('空出 8.4 GB', t, 23.6);
}

// ---------------------------------------------------------------- shot 7: install

const DMG = { x: 370, y: 210, w: 1180, h: 660 };
const APP_AT = [700, 520], APPS_AT = [1220, 520];

function shot7(t) {
  const lt = t - 26;
  const z = lerp(1.0, 1.08, sineIO(prog(lt, 0, 1.4))) * impact(t, 26);
  camera(960, 540, z);
  worldGrid(-400, -300, 2400, 1500);

  // window
  ctx.save();
  ctx.shadowColor = 'rgba(0,0,0,0.6)';
  ctx.shadowBlur = 70;
  ctx.shadowOffsetY = 26;
  ctx.fillStyle = '#121A2C';
  rr(DMG.x, DMG.y, DMG.w, DMG.h, 22);
  ctx.fill();
  ctx.restore();
  ctx.strokeStyle = 'rgba(170,190,255,0.16)';
  ctx.lineWidth = 1.5;
  rr(DMG.x, DMG.y, DMG.w, DMG.h, 22);
  ctx.stroke();
  ctx.fillStyle = 'rgba(255,255,255,0.03)';
  rr(DMG.x, DMG.y, DMG.w, 60, [22, 22, 0, 0]);
  ctx.fill();
  ['#FF5F57', '#FEBC2E', '#28C840'].forEach((c, i) => {
    ctx.fillStyle = c;
    ctx.beginPath(); ctx.arc(DMG.x + 32 + i * 26, DMG.y + 30, 8, 0, Math.PI * 2); ctx.fill();
  });
  text('AgentSweep 0.1.0', 960, DMG.y + 39, { size: 22, weight: 600, color: C.muted, align: 'center' });
  text('github.com/ai-suifeng/agent-clean-mac', 960, DMG.y + DMG.h - 52, { size: 26, color: C.dim, align: 'center', font: MONO });

  // dashed arrow, always drifting
  ctx.save();
  ctx.setLineDash([14, 14]);
  ctx.lineDashOffset = -t * 40;
  ctx.strokeStyle = 'rgba(143,216,255,0.5)';
  ctx.lineWidth = 4;
  ctx.beginPath(); ctx.moveTo(860, 520); ctx.lineTo(1060, 520); ctx.stroke();
  ctx.restore();
  ctx.fillStyle = 'rgba(143,216,255,0.5)';
  ctx.beginPath(); ctx.moveTo(1078, 520); ctx.lineTo(1054, 506); ctx.lineTo(1054, 534); ctx.closePath(); ctx.fill();

  // Applications folder, bounces when the app lands
  const land = prog(lt, 2.0, 0.42);
  const bounce = land > 0 ? 1 + 0.14 * Math.sin(land * Math.PI) * (1 - land) * 2 : 1;
  folder(APPS_AT[0], APPS_AT[1], 230, C.ice, { glyph: 'A', scale: bounce });
  text('应用程序', APPS_AT[0], APPS_AT[1] + 160, { size: 26, weight: 500, align: 'center' });
  if (land > 0) {
    ctx.strokeStyle = `rgba(143,216,255,${0.7 * (1 - land)})`;
    ctx.lineWidth = 3;
    ctx.beginPath(); ctx.arc(APPS_AT[0], APPS_AT[1], 140 + 120 * land, 0, Math.PI * 2); ctx.stroke();
    const ok = outBack(prog(lt, 2.25, 0.3));
    if (ok > 0) {
      ctx.save();
      ctx.translate(APPS_AT[0] + 92, APPS_AT[1] - 78);
      ctx.scale(ok, ok);
      ctx.fillStyle = C.green;
      ctx.beginPath(); ctx.arc(0, 0, 26, 0, Math.PI * 2); ctx.fill();
      ctx.strokeStyle = '#0B2414';
      ctx.lineWidth = 6;
      ctx.lineCap = 'round';
      ctx.beginPath(); ctx.moveTo(-11, 1); ctx.lineTo(-3, 9); ctx.lineTo(12, -8); ctx.stroke();
      ctx.restore();
    }
  }

  // the app icon and its dragged copy
  const grab = lt >= 0.75;
  ctx.globalAlpha = grab ? 0.35 : 1;
  ctx.drawImage(icon, APP_AT[0] - 115, APP_AT[1] - 115, 230, 230);
  ctx.globalAlpha = 1;
  text('AgentSweep', APP_AT[0], APP_AT[1] + 160, { size: 26, weight: 500, align: 'center' });

  // pointer path: in → press → arc to the folder → drop
  let px, py;
  if (lt < 0.7) {
    const k = sineIO(prog(lt, 0.15, 0.55));
    px = lerp(1500, APP_AT[0] + 10, k); py = lerp(860, APP_AT[1] + 10, k);
  } else {
    const k = sineIO(prog(lt, 0.8, 1.15));
    const u = 1 - k;
    px = u * u * (APP_AT[0] + 10) + 2 * u * k * 960 + k * k * (APPS_AT[0] + 10);
    py = u * u * (APP_AT[1] + 10) + 2 * u * k * 330 + k * k * (APPS_AT[1] + 10);
  }
  if (grab && lt < 2.25) {
    const sink = prog(lt, 2.0, 0.22);
    const s = lerp(0.92, 0.2, sink);
    ctx.globalAlpha = 0.9 * (1 - sink);
    ctx.drawImage(icon, px - 10 - 115 * s, py - 10 - 115 * s, 230 * s, 230 * s);
    ctx.globalAlpha = 1;
  }
  const press = lt > 0.7 && lt < 2.0 ? 0.9 : 1;
  cursorArrow(px, py, press);
  caption('开源 · 免费', t, 26.4);
}

// ================================================================ vertical cut (1080×1920)

// Free-space column: tool blocks stack from the bottom, the empty top is what is left.
const COL = { x: 250, y: 560, w: 250, h: 900 };
const CARD_V = { x: 90, y: 300, w: 900, h: 1240 };

function blockSpansV(keep) {
  let y = COL.y + COL.h;
  return BLOCKS.map((b) => {
    const h = (b[1] * keep / FREE0) * COL.h;
    y -= h;
    return { y, h };
  });
}

function meterV(t, landed, keep) {
  const used = BLOCKS.reduce((s, b, i) => s + b[1] * landed[i] * keep, 0);
  const free = FREE0 - used;
  const low = free < 5;

  ctx.save();
  ctx.shadowColor = 'rgba(0,0,0,0.55)';
  ctx.shadowBlur = 60;
  ctx.shadowOffsetY = 24;
  ctx.fillStyle = C.panel;
  rr(CARD_V.x, CARD_V.y, CARD_V.w, CARD_V.h, 36);
  ctx.fill();
  ctx.restore();
  ctx.strokeStyle = C.line;
  ctx.lineWidth = 1.5;
  rr(CARD_V.x, CARD_V.y, CARD_V.w, CARD_V.h, 36);
  ctx.stroke();

  ctx.fillStyle = '#273250';
  rr(150, 360, 92, 68, 12);
  ctx.fill();
  ctx.fillStyle = C.ice;
  ctx.beginPath(); ctx.arc(220, 410, 5, 0, Math.PI * 2); ctx.fill();
  text('Macintosh HD', 268, 402, { size: 46, weight: 600 });
  text(`${DISK} GB · 剩余空间`, 270, 446, { size: 28, color: C.muted });

  const col = low ? C.red : free > 9 ? C.green : C.fg;
  text('可用', 150, 520, { size: 32, color: C.muted });
  text(free.toFixed(1), 234, 524, { size: 84, weight: 300, color: col, font: MONO });
  ctx.font = `300 84px ${MONO}`;
  text('GB', 234 + ctx.measureText(free.toFixed(1)).width + 14, 524, { size: 32, color: C.muted });

  // column well; empty space stripes drift upward
  ctx.save();
  rr(COL.x, COL.y, COL.w, COL.h, 22);
  ctx.clip();
  ctx.fillStyle = C.well;
  ctx.fillRect(COL.x, COL.y, COL.w, COL.h);
  ctx.strokeStyle = low ? 'rgba(248,113,113,0.28)' : free > 9 ? 'rgba(74,222,128,0.22)' : 'rgba(143,216,255,0.12)';
  ctx.lineWidth = 7;
  const shift = (t * 40) % 28;
  for (let y = COL.y - 300 - shift; y < COL.y + COL.h + 300; y += 28) {
    ctx.beginPath(); ctx.moveTo(COL.x, y + 60); ctx.lineTo(COL.x + COL.w, y); ctx.stroke();
  }
  const spans = blockSpansV(keep);
  BLOCKS.forEach((b, i) => {
    if (!landed[i]) return;
    const { y, h } = spans[i];
    ctx.fillStyle = b[2];
    ctx.fillRect(COL.x, y + 2, COL.w, Math.max(0, h - 3));
    ctx.fillStyle = 'rgba(255,255,255,0.12)';
    ctx.fillRect(COL.x, y + 2, COL.w, 6);
  });
  ctx.restore();
  ctx.strokeStyle = low ? `rgba(248,113,113,${0.55 + 0.35 * Math.sin(t * 9) ** 2})` : C.line;
  ctx.lineWidth = low ? 4 : 1.5;
  rr(COL.x, COL.y, COL.w, COL.h, 22);
  ctx.stroke();

  // labels to the right; the four small blocks share one label
  const lab = (name, gb, y0, y1, color, on) => {
    if (!on) return;
    const my = (y0 + y1) / 2;
    ctx.fillStyle = color;
    rr(COL.x + COL.w + 22, y0 + 4, 6, Math.max(8, y1 - y0 - 8), 3);
    ctx.fill();
    text(name, COL.x + COL.w + 50, my - 4, { size: 36, weight: 600 });
    text(`${(gb * keep).toFixed(gb * keep >= 10 ? 1 : 2)} GB`, COL.x + COL.w + 50, my + 38, { size: 30, color: C.muted, font: MONO });
  };
  lab('开发缓存', BLOCKS[0][1], spans[0].y, spans[0].y + spans[0].h, BLOCKS[0][2], landed[0]);
  lab('Codex', BLOCKS[1][1], spans[1].y, spans[1].y + spans[1].h, BLOCKS[1][2], landed[1]);
  lab('Cursor', BLOCKS[2][1], spans[2].y, spans[2].y + spans[2].h, BLOCKS[2][2], landed[2]);
  const rest = BLOCKS.slice(3).reduce((s, b) => s + b[1], 0);
  lab('ZCode、Kimi 等', rest, spans[6].y, spans[3].y + spans[3].h, BLOCKS[3][2], landed[6]);
  return free;
}

function alertSheetV(t, t0) {
  const s = slam(t, t0);
  if (!s) return;
  ctx.save();
  ctx.fillStyle = `rgba(3,5,10,${0.45 * prog(t, t0, 0.15)})`;
  ctx.fillRect(-600, -600, W + 1200, H + 1200);
  ctx.translate(540, 980);
  ctx.scale(s, s);
  ctx.shadowColor = 'rgba(0,0,0,0.7)';
  ctx.shadowBlur = 70;
  ctx.shadowOffsetY = 28;
  ctx.fillStyle = '#262D40';
  rr(-400, -230, 800, 460, 32);
  ctx.fill();
  ctx.shadowBlur = 0;
  ctx.shadowOffsetY = 0;
  ctx.strokeStyle = 'rgba(255,255,255,0.12)';
  ctx.lineWidth = 1.5;
  ctx.stroke();
  ctx.fillStyle = C.yellow;
  ctx.beginPath(); ctx.moveTo(0, -192); ctx.lineTo(46, -112); ctx.lineTo(-46, -112); ctx.closePath(); ctx.fill();
  text('!', 0, -122, { size: 48, weight: 800, color: '#1B1405', align: 'center' });
  text('启动磁盘几乎已满', 0, -40, { size: 46, weight: 600, align: 'center' });
  text('这台 Mac 只剩 2.3 GB 可用空间。', 0, 16, { size: 30, color: C.muted, align: 'center' });
  ctx.fillStyle = '#3A4258';
  rr(-350, 90, 335, 80, 16); ctx.fill();
  text('以后', -182, 142, { size: 32, weight: 600, align: 'center' });
  ctx.fillStyle = '#4C8DF0';
  rr(15, 90, 335, 80, 16); ctx.fill();
  text('管理…', 182, 142, { size: 32, weight: 600, align: 'center' });
  ctx.restore();
}

function shot1v(t) {
  const alertShake = t >= 3.0 ? Math.max(0, 1 - (t - 3.0) / 0.3) : 0;
  const knock = DROP.reduce((k, d) => k + Math.max(0, 1 - Math.abs(t - d - FALL) / 0.08) * (t >= d + FALL ? 1 : 0), 0);
  // follow the stack as it rises, then pull out to the whole card
  const spans = blockSpansV(1);
  let i = 0;
  while (i < BLOCKS.length - 1 && t >= DROP[i + 1]) i++;
  const tops = spans.map((sp) => sp.y);
  const from = i === 0 ? COL.y + COL.h : tops[i - 1];
  const followY = lerp(from, tops[i], sineIO(prog(t, DROP[i], 0.3)));
  const out = outQuint(prog(t, 2.55, 0.5));
  camera(lerp(COL.x + COL.w / 2 + 120, 540, out), lerp(followY - 80, 920, out), lerp(1.7, 1.0, out) * impact(t, 0),
    Math.sin(t * 90) * 12 * alertShake, Math.cos(t * 77) * 8 * alertShake + knock * 6);
  worldGrid(-600, -600, 1700, 2600);
  meterV(t, DROP.map((d) => (t >= d + FALL ? 1 : 0)), 1);
  // blocks drop in through the column's mouth, never over the readout above it
  ctx.save();
  ctx.beginPath();
  ctx.rect(COL.x - 20, COL.y, COL.w + 40, COL.h);
  ctx.clip();
  BLOCKS.forEach((b, k) => {
    const p = prog(t, DROP[k], FALL);
    if (p <= 0 || p >= 1) return;
    const { y, h } = spans[k];
    const yy = y - 760 * (1 - p * p);
    ctx.fillStyle = b[2];
    rr(COL.x, yy, COL.w, Math.max(6, h - 3), 12);
    ctx.fill();
  });
  ctx.restore();
  alertSheetV(t, 3.0);
}

const ROW_Y = (i) => 420 + i * 330;

function shot2v(t) {
  const lt = t - 4;
  const fy = lt < 1.2 ? 960
    : lt < 1.9 ? lerp(960, 1500, sineIO(prog(lt, 1.2, 0.7)))
      : lt < 2.6 ? 1500
        : lerp(1500, 1980, sineIO(prog(lt, 2.6, 0.7)));
  camera(540, fy, impact(t, 4));
  worldGrid(-600, -600, 1700, 3400);
  text('~  主目录 · 隐藏文件夹', 90, 250, { size: 36, color: C.muted, font: MONO });
  ctx.strokeStyle = C.line;
  ctx.lineWidth = 1.5;
  ctx.beginPath(); ctx.moveTo(90, 284); ctx.lineTo(990, 284); ctx.stroke();
  FOLDERS.forEach(([name, size, tint], i) => {
    const y = ROW_Y(i);
    const enter = i < 4 ? 0.05 + i * 0.16 : i < 6 ? 1.45 + (i - 4) * 0.16 : 2.85 + (i - 6) * 0.16;
    const p = prog(lt, enter, 0.32);
    if (p <= 0) return;
    const dx = 420 * (1 - outCubic(p));      // rows slide in from the right, like a list filling
    const a = Math.min(1, p * 2);
    ctx.save();
    ctx.globalAlpha = a;
    ctx.fillStyle = 'rgba(28,36,56,0.75)';
    rr(90 + dx, y - 130, 900, 260, 28);
    ctx.fill();
    ctx.strokeStyle = C.line;
    ctx.stroke();
    ctx.restore();
    folder(230 + dx, y, 190, tint, { alpha: a, scale: lerp(0.7, 1, outBack(p)) });
    text(name, 370 + dx, y - 6, { size: 50, weight: 600, font: MONO, alpha: a });
    text(size, 370 + dx, y + 52, { size: 38, color: C.muted, font: MONO, alpha: a });
    const q = prog(lt, enter + 0.4, 0.28);
    if (q > 0) {
      ctx.save();
      ctx.translate(900 + dx, y);
      ctx.scale(outBack(q, 2.4), outBack(q, 2.4));
      ctx.fillStyle = C.orange;
      ctx.beginPath(); ctx.arc(0, 0, 44, 0, Math.PI * 2); ctx.fill();
      text('?', 0, 20, { size: 60, weight: 800, color: '#1B1405', align: 'center' });
      ctx.restore();
    }
  });
  caption('哪些能删？', t, 4.5);
}

function shot3v(t, img) {
  // pull out from the counter to the orbit, then glide across to the tool list filling in
  const p = sineIO(prog(t, 8.15, 1.15));
  const g = sineIO(prog(t, 10.9, 0.8));
  const LOG = fw(330, 700);
  const fx = lerp(RING[0], LOG[0], g), fy = lerp(RING[1], LOG[1], g);
  camera(fx, fy, lerp(3.2, 1.85, p) * impact(t, 8));
  worldGrid(-600, -600, 2600, 1700);
  footageWindow(img);
  caption('认识 14 种工具', t, 9.4);
}

// Shots 4–5 vertical: two crops of the same recording stacked, the ring on top and the
// cleaning list below, so every item stays readable on a tall screen.
const RING_DST = { x: 40, y: 110, w: 1000, h: 860 };
const LIST_DST = { x: 40, y: 1000, w: 1000, h: 660 };
const LIST_W = 780;   // the list column in the recording, in layout pixels

function ringCrop(z) {
  const w = 700 / z, h = 602 / z;
  return { x: 799 - w / 2, y: 544 - h / 2, w, h };
}

function listCrop(scroll) {
  return { x: 1196, y: 150 + scroll, w: LIST_W, h: LIST_W * LIST_DST.h / LIST_DST.w };
}

function cropPanel(img, crop, dst) {
  const k = img.naturalWidth / FOOT_W;
  ctx.save();
  ctx.shadowColor = 'rgba(0,0,0,0.6)';
  ctx.shadowBlur = 50;
  ctx.shadowOffsetY = 18;
  ctx.fillStyle = C.deep;
  rr(dst.x, dst.y, dst.w, dst.h, 30);
  ctx.fill();
  ctx.restore();
  ctx.save();
  rr(dst.x, dst.y, dst.w, dst.h, 30);
  ctx.clip();
  ctx.drawImage(img, crop.x * k, crop.y * k, crop.w * k, crop.h * k, dst.x, dst.y, dst.w, dst.h);
  ctx.restore();
  ctx.strokeStyle = 'rgba(170,190,255,0.18)';
  ctx.lineWidth = 1.5;
  rr(dst.x, dst.y, dst.w, dst.h, 30);
  ctx.stroke();
}

const toDst = (crop, dst, px, py) => [dst.x + (px - crop.x) * dst.w / crop.w, dst.y + (py - crop.y) * dst.h / crop.h];

const CALLOUTS_V = [
  { px: [842, 302], to: [470, 160], label: '可安全删除', color: C.green, t0: 15.3, side: 'left' },
  { px: [1043, 443], to: [1010, 640], label: '旧会话', color: C.yellow, t0: 15.8, side: 'left' },
  { px: [559, 474], to: [80, 700], label: '受保护', color: C.red, t0: 16.3, side: 'right' },
];

function shot4v(t, img) {
  camera(540, 960, impact(t, 13));
  worldGrid(-600, -600, 1700, 2600);
  const rc = ringCrop(lerp(1.0, 1.08, sineIO(prog(t, 14.0, 1.2))));
  cropPanel(img, rc, RING_DST);
  // after the callouts, the list scrolls to show more items
  cropPanel(img, listCrop(260 * sineIO(prog(t, 16.6, 1.2))), LIST_DST);
  for (const c of CALLOUTS_V) callout(t, { ...c, at: toDst(rc, RING_DST, c.px[0], c.px[1]) });
  caption('每一项写清楚', t, 13.4);
}

function shot5v(t, img) {
  // the ring panel pushes into the hole; the list stays in view and gets struck through when done
  camera(540, 960, 1);
  worldGrid(-600, -600, 1700, 2600);
  cropPanel(img, ringCrop(lerp(1.05, 1.6, outCubic(prog(t, 18.25, 0.3)))), RING_DST);
  cropPanel(img, listCrop(0), LIST_DST);
  caption('移到废纸篓', t, 18.6);
}

const DOCK_V = { x: 150, y: 1580, w: 780, h: 132 };
const TRASH_V = [DOCK_V.x + DOCK_V.w - 74, DOCK_V.y + DOCK_V.h / 2];

function dockV(full, lid) {
  ctx.save();
  ctx.fillStyle = 'rgba(28,36,56,0.9)';
  ctx.shadowColor = 'rgba(0,0,0,0.5)';
  ctx.shadowBlur = 40;
  rr(DOCK_V.x, DOCK_V.y, DOCK_V.w, DOCK_V.h, 34);
  ctx.fill();
  ctx.restore();
  ['#3A4D7A', '#10A37F', '#8B8BFF', '#D97757'].forEach((c, i) => {
    const x = DOCK_V.x + 28 + i * 118;
    ctx.fillStyle = c;
    rr(x, DOCK_V.y + 20, 94, 94, 24);
    ctx.fill();
  });
  ctx.drawImage(icon, DOCK_V.x + 28 + 4 * 118 - 6, DOCK_V.y + 14, 106, 106);
  ctx.fillStyle = 'rgba(255,255,255,0.18)';
  ctx.fillRect(DOCK_V.x + DOCK_V.w - 150, DOCK_V.y + 26, 2, 80);
  trashCan(TRASH_V[0], TRASH_V[1] + 4, full, lid);
}

function shot6v(t) {
  const lt = t - 22;
  const pull = outQuint(prog(lt, 1.0, 1.3));
  camera(lerp(TRASH_V[0] - 120, 540, pull), lerp(TRASH_V[1] - 160, 1080, pull), lerp(1.8, 0.86, pull) * impact(t, 22));
  worldGrid(-600, -600, 1700, 2600);
  const shrink = outCubic(prog(lt, 1.35, 1.1));
  const keep = 1 - shrink * (FREED / AGENT);
  const free = meterV(t, BLOCKS.map(() => 1), keep);
  if (shrink > 0) {
    const top = blockSpansV(keep)[6].y;
    text(`+${(free - (FREE0 - AGENT)).toFixed(1)} GB`, COL.x + COL.w / 2, (COL.y + top) / 2 + 16, { size: 44, weight: 700, color: C.green, align: 'center', font: MONO, alpha: shrink });
  }
  const empty = prog(lt, 0.8, 0.01);
  const lid = Math.sin(prog(lt, 0.8, 0.5) * Math.PI) * 0.6;
  dockV(1 - empty, lid);
  const menu = prog(lt, 0.3, 0.15) * (1 - prog(lt, 0.85, 0.1));
  if (menu > 0) {
    ctx.save();
    ctx.globalAlpha = menu;
    ctx.fillStyle = '#2B3247';
    rr(TRASH_V[0] - 150, TRASH_V[1] - 172, 240, 66, 14);
    ctx.fill();
    if (prog(lt, 0.62, 0.05) > 0) { ctx.fillStyle = '#4C8DF0'; rr(TRASH_V[0] - 144, TRASH_V[1] - 166, 228, 54, 10); ctx.fill(); }
    text('清空废纸篓', TRASH_V[0] - 30, TRASH_V[1] - 128, { size: 28, weight: 600, align: 'center' });
    ctx.restore();
  }
  if (lt >= 0.8) {
    const r = seeded(5);
    for (let i = 0; i < 14; i++) {
      const a = -Math.PI / 2 + (r() - 0.5) * 1.6, sp = 160 + r() * 260, k = prog(lt, 0.8 + r() * 0.08, 0.7);
      if (k <= 0 || k >= 1) continue;
      ctx.globalAlpha = 1 - k;
      ctx.fillStyle = ['#E6EBF7', '#C9D3EA', '#8FD8FF'][i % 3];
      ctx.beginPath();
      ctx.arc(TRASH_V[0] + Math.cos(a) * sp * k, TRASH_V[1] - 30 + Math.sin(a) * sp * k + 220 * k * k, 9 * (1 - k * 0.5), 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }
  const cx = lt < 0.3 ? lerp(TRASH_V[0] - 160, TRASH_V[0] + 8, sineIO(prog(lt, 0, 0.3))) : lerp(TRASH_V[0] + 8, TRASH_V[0] - 30, sineIO(prog(lt, 0.4, 0.22)));
  const cy = lt < 0.3 ? lerp(TRASH_V[1] + 60, TRASH_V[1] - 6, sineIO(prog(lt, 0, 0.3)))
    : lerp(TRASH_V[1] - 6, TRASH_V[1] - 140, sineIO(prog(lt, 0.4, 0.22)));
  const press = (lt > 0.25 && lt < 0.33) || (lt > 0.7 && lt < 0.78) ? 0.88 : 1;
  cursorArrow(cx, cy, press * (1 - prog(lt, 1.2, 0.3)));
  caption('空出 8.4 GB', t, 23.6);
}

const DMG_V = { x: 110, y: 330, w: 860, h: 1220 };
const APP_V = [540, 660], APPS_V = [540, 1170];

function shot7v(t) {
  const lt = t - 26;
  camera(540, 940, lerp(1.0, 1.07, sineIO(prog(lt, 0, 1.4))) * impact(t, 26));
  worldGrid(-600, -600, 1700, 2600);
  ctx.save();
  ctx.shadowColor = 'rgba(0,0,0,0.6)';
  ctx.shadowBlur = 70;
  ctx.shadowOffsetY = 26;
  ctx.fillStyle = '#121A2C';
  rr(DMG_V.x, DMG_V.y, DMG_V.w, DMG_V.h, 30);
  ctx.fill();
  ctx.restore();
  ctx.strokeStyle = 'rgba(170,190,255,0.16)';
  ctx.lineWidth = 1.5;
  rr(DMG_V.x, DMG_V.y, DMG_V.w, DMG_V.h, 30);
  ctx.stroke();
  ['#FF5F57', '#FEBC2E', '#28C840'].forEach((c, i) => {
    ctx.fillStyle = c;
    ctx.beginPath(); ctx.arc(DMG_V.x + 40 + i * 32, DMG_V.y + 40, 10, 0, Math.PI * 2); ctx.fill();
  });
  text('AgentSweep 0.1.0', 540, DMG_V.y + 50, { size: 30, weight: 600, color: C.muted, align: 'center' });
  text('github.com/ai-suifeng', 540, DMG_V.y + DMG_V.h - 100, { size: 36, color: C.muted, align: 'center', font: MONO });
  text('/agent-clean-mac', 540, DMG_V.y + DMG_V.h - 50, { size: 36, color: C.muted, align: 'center', font: MONO });

  ctx.save();
  ctx.setLineDash([16, 16]);
  ctx.lineDashOffset = -t * 40;
  ctx.strokeStyle = 'rgba(143,216,255,0.5)';
  ctx.lineWidth = 5;
  ctx.beginPath(); ctx.moveTo(540, 860); ctx.lineTo(540, 990); ctx.stroke();
  ctx.restore();
  ctx.fillStyle = 'rgba(143,216,255,0.5)';
  ctx.beginPath(); ctx.moveTo(540, 1012); ctx.lineTo(522, 984); ctx.lineTo(558, 984); ctx.closePath(); ctx.fill();

  const land = prog(lt, 2.0, 0.42);
  const bounce = land > 0 ? 1 + 0.14 * Math.sin(land * Math.PI) * (1 - land) * 2 : 1;
  folder(APPS_V[0], APPS_V[1], 270, C.ice, { glyph: 'A', scale: bounce });
  text('应用程序', APPS_V[0], APPS_V[1] + 186, { size: 36, weight: 500, align: 'center' });
  if (land > 0) {
    ctx.strokeStyle = `rgba(143,216,255,${0.7 * (1 - land)})`;
    ctx.lineWidth = 3;
    ctx.beginPath(); ctx.arc(APPS_V[0], APPS_V[1], 160 + 140 * land, 0, Math.PI * 2); ctx.stroke();
    const ok = outBack(prog(lt, 2.25, 0.3));
    if (ok > 0) {
      ctx.save();
      ctx.translate(APPS_V[0] + 112, APPS_V[1] - 92);
      ctx.scale(ok, ok);
      ctx.fillStyle = C.green;
      ctx.beginPath(); ctx.arc(0, 0, 32, 0, Math.PI * 2); ctx.fill();
      ctx.strokeStyle = '#0B2414';
      ctx.lineWidth = 7;
      ctx.lineCap = 'round';
      ctx.beginPath(); ctx.moveTo(-13, 1); ctx.lineTo(-4, 11); ctx.lineTo(14, -10); ctx.stroke();
      ctx.restore();
    }
  }
  const grab = lt >= 0.75;
  ctx.globalAlpha = grab ? 0.35 : 1;
  ctx.drawImage(icon, APP_V[0] - 135, APP_V[1] - 135, 270, 270);
  ctx.globalAlpha = 1;
  text('AgentSweep', APP_V[0], APP_V[1] + 186, { size: 36, weight: 500, align: 'center' });

  let px, py;
  if (lt < 0.7) {
    const k = sineIO(prog(lt, 0.15, 0.55));
    px = lerp(900, APP_V[0] + 10, k); py = lerp(1500, APP_V[1] + 10, k);
  } else {
    const k = sineIO(prog(lt, 0.8, 1.15));
    const u = 1 - k;
    px = u * u * (APP_V[0] + 10) + 2 * u * k * 820 + k * k * (APPS_V[0] + 10);
    py = u * u * (APP_V[1] + 10) + 2 * u * k * 920 + k * k * (APPS_V[1] + 10);
  }
  if (grab && lt < 2.25) {
    const sink = prog(lt, 2.0, 0.22);
    const s = lerp(0.92, 0.2, sink);
    ctx.globalAlpha = 0.9 * (1 - sink);
    ctx.drawImage(icon, px - 10 - 135 * s, py - 10 - 135 * s, 270 * s, 270 * s);
    ctx.globalAlpha = 1;
  }
  cursorArrow(px, py, (lt > 0.7 && lt < 2.0 ? 0.9 : 1) * 1.25);
  caption('开源 · 免费', t, 26.4);
}

// ---------------------------------------------------------------- frame

window.prepare = async (t) => {
  const ft = footageTime(t);
  if (ft !== null) await loadFrame(footIndex(ft));
};

window.renderFrame = (t) => {
  backdrop();
  const ft = footageTime(t);
  const img = ft !== null ? frames.get(footIndex(ft)) : null;
  const S = V ? [shot1v, shot2v, shot3v, shot4v, shot5v, shot6v, shot7v] : [shot1, shot2, shot3, shot4, shot5, shot6, shot7];
  const k = t < 4 ? 0 : t < 8 ? 1 : t < 13 ? 2 : t < 18 ? 3 : t < 22 ? 4 : t < 26 ? 5 : 6;
  S[k](t, img);
  screen();
};

icon.decode().then(() => { window.__ready = true; }, (e) => { window.__bootFailed = 'icon: ' + e; });

// Live preview when opened in a browser without ?render=1.
if (!location.search.includes('render=1')) {
  const start = performance.now();
  const loop = async () => {
    const t = ((performance.now() - start) / 1000) % TOTAL;
    await window.prepare(t);
    window.renderFrame(t);
    requestAnimationFrame(loop);
  };
  icon.decode().then(loop);
}
