// Suoni sintetizzati (niente file audio): dadi, gong, lamento dei fantasmi, esorcismo, infestazione, tocca a te.
let ctx = null;
export function sbloccaAudio() {
  try { ctx = ctx || new (window.AudioContext || window.webkitAudioContext)(); if (ctx.state === 'suspended') ctx.resume(); } catch (e) { /* ok */ }
}
function nota(freq, dur, tipo = 'sine', vol = 0.15, quando = 0, fine = null) {
  if (!ctx) return;
  const t = ctx.currentTime + quando;
  const o = ctx.createOscillator();
  const g = ctx.createGain();
  o.type = tipo;
  o.frequency.setValueAtTime(freq, t);
  if (fine) o.frequency.exponentialRampToValueAtTime(fine, t + dur);
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(vol, t + 0.02);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  o.connect(g).connect(ctx.destination);
  o.start(t);
  o.stop(t + dur + 0.05);
}
function rumore(dur, vol = 0.2, quando = 0, filtro = 1200) {
  if (!ctx) return;
  const n = Math.floor(ctx.sampleRate * dur);
  const b = ctx.createBuffer(1, n, ctx.sampleRate);
  const d = b.getChannelData(0);
  for (let i = 0; i < n; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / n);
  const s = ctx.createBufferSource();
  s.buffer = b;
  const f = ctx.createBiquadFilter();
  f.type = 'lowpass';
  f.frequency.value = filtro;
  const g = ctx.createGain();
  g.gain.value = vol;
  s.connect(f).connect(g).connect(ctx.destination);
  s.start(ctx.currentTime + quando);
}
export function suona(n) {
  if (!ctx) return;
  switch (n) {
    case 'dado': for (let i = 0; i < 5; i++) rumore(0.05, 0.25, i * 0.09, 3000); break;
    case 'gong': nota(110, 2.2, 'sine', 0.25); nota(166, 1.8, 'sine', 0.1); nota(220, 1.2, 'triangle', 0.06); break;
    case 'fantasma': nota(520, 1.1, 'sine', 0.07, 0, 300); nota(390, 1.2, 'sine', 0.05, 0.15, 220); break;
    case 'esorcismo': [784, 988, 1175, 1568].forEach((f, i) => nota(f, 0.5, 'triangle', 0.1, i * 0.08)); break;
    case 'infesta': nota(70, 1.2, 'sawtooth', 0.08, 0, 45); rumore(0.9, 0.12, 0, 400); break;
    case 'maledizione': nota(140, 0.7, 'square', 0.06, 0, 70); break;
    case 'qi': nota(330, 0.25, 'triangle', 0.12); nota(247, 0.35, 'triangle', 0.12, 0.12); break;
    case 'vittoria': [523, 659, 784, 1047, 1319].forEach((f, i) => nota(f, 0.6, 'triangle', 0.13, i * 0.15)); nota(110, 2.5, 'sine', 0.2, 0.7); break;
    case 'sconfitta': [330, 262, 196, 131].forEach((f, i) => nota(f, 0.7, 'sawtooth', 0.06, i * 0.3)); break;
    case 'tocca': nota(660, 0.15, 'triangle', 0.18); nota(880, 0.3, 'triangle', 0.18, 0.16); break;
    case 'clic': nota(1200, 0.05, 'triangle', 0.05); break;
    default: nota(440, 0.1);
  }
}
