(() => {
const NS = 'http://www.w3.org/2000/svg';
const el = (tag, attrs, parent) => { const n = document.createElementNS(NS, tag);
  for (const k in attrs) n.setAttribute(k, attrs[k]); if (parent) parent.appendChild(n); return n; };
const fmtDay = t => new Date(t * 1000).toLocaleDateString(undefined, {day: 'numeric', month: 'short'});
const fmtTime = t => new Date(t * 1000).toLocaleString(undefined, {day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit'});
const fmtNum = v => Math.abs(v) >= 10000 ? (v / 1000).toFixed(0) + 'K' : (+v.toPrecision(4)).toLocaleString();
function niceMax(v) { if (v <= 0) return 1; const p = Math.pow(10, Math.floor(Math.log10(v)));
  for (const m of [1, 2, 2.5, 5, 10]) if (m * p >= v) return m * p; return 10 * p; }
function tip(box) { const t = document.createElement('div'); t.className = 'tip'; box.appendChild(t); return t; }
function showTip(t, box, x, y, rows) { t.replaceChildren(); for (const r of rows) { const d = document.createElement('div');
  if (r.color) { const i = document.createElement('i'); i.style.background = r.color; d.appendChild(i); }
  if (r.value !== undefined) { const b = document.createElement('b'); b.textContent = r.value + ' '; d.appendChild(b); }
  d.appendChild(document.createTextNode(r.text)); t.appendChild(d); }
  t.style.display = 'block'; const w = t.offsetWidth;
  t.style.left = Math.min(Math.max(0, x + 12), box.clientWidth - w) + 'px'; t.style.top = (y + 12) + 'px'; }
// Ticks on local midnights (or whole hours for a short range), at most one per 80px.
function timeTicks(x0, x1, w) { const most = Math.max(2, Math.floor(w / 80)), span = x1 - x0, out = [];
  if (span > 2 * 86400) { const step = [1, 2, 7, 14, 28].find(d => span / (d * 86400) <= most) || 56;
    const d = new Date(x0 * 1000); d.setHours(24, 0, 0, 0);
    for (; d / 1000 <= x1; d.setDate(d.getDate() + step)) out.push({t: d / 1000, label: fmtDay(d / 1000)}); }
  else { const step = [1, 2, 3, 6, 12, 24].find(h => span / (h * 3600) <= most) || 48;
    const d = new Date(x0 * 1000); d.setMinutes(60, 0, 0);
    while (d.getHours() % step) d.setHours(d.getHours() + 1);
    for (; d / 1000 <= x1; d.setHours(d.getHours() + step))
      out.push({t: d / 1000, label: d.getHours() === 0 || !out.length ? fmtDay(d / 1000) : d.toLocaleTimeString(undefined, {hour: '2-digit', minute: '2-digit'})}); }
  return out; }

function lineChart(box, spec) {
  const W = box.clientWidth, H = spec.kind === 'step' ? 220 : 160, m = {l: 44, r: 12, t: 10, b: 24};
  const pts = spec.series.flatMap(s => s.pts);
  let x0 = Math.min(...pts.map(p => p[0])), x1 = Math.max(...pts.map(p => p[0]));
  if (x1 === x0) { x0 -= 3600; x1 += 3600; }
  const vals = pts.map(p => p[1]).concat(spec.baseline != null ? [spec.baseline] : []);
  // Counts get whole-number ticks.
  const y1 = spec.kind === 'step' ? 4 * Math.max(1, Math.ceil(Math.max(...vals) / 4)) : niceMax(Math.max(...vals));
  const X = t => m.l + (t - x0) / (x1 - x0) * (W - m.l - m.r), Y = v => H - m.b - v / y1 * (H - m.t - m.b);
  if (spec.series.length > 1) { const lg = document.createElement('div'); lg.className = 'legend';
    for (const s of spec.series) { const sp = document.createElement('span'); const i = document.createElement('i');
      i.style.background = s.color; sp.appendChild(i); sp.appendChild(document.createTextNode(s.name)); lg.appendChild(sp); }
    box.appendChild(lg); }
  const svg = el('svg', {width: W, height: H, role: 'img'}, box);
  for (let i = 0; i <= 4; i++) { const v = y1 * i / 4, y = Y(v);
    el('line', {x1: m.l, x2: W - m.r, y1: y, y2: y, stroke: 'var(--grid)', 'stroke-width': 1}, svg);
    el('text', {x: m.l - 6, y: y + 4, 'text-anchor': 'end'}, svg).textContent = fmtNum(v); }
  for (const tk of timeTicks(x0, x1, W - m.l - m.r))
    el('text', {x: X(tk.t), y: H - 6, 'text-anchor': 'middle'}, svg).textContent = tk.label;
  for (const mk of spec.markers || []) { const x = X(mk.t);
    el('line', {x1: x, x2: x, y1: m.t, y2: H - m.b, stroke: 'var(--accent-2)', 'stroke-width': 1}, svg);
    el('text', {x: x + 3, y: m.t + 9}, svg).textContent = mk.label; }
  if (spec.baseline != null) { const y = Y(spec.baseline);
    el('line', {x1: m.l, x2: W - m.r, y1: y, y2: y, stroke: 'var(--ink-2)', 'stroke-width': 1}, svg);
    el('text', {x: m.l + 4, y: y - 4}, svg).textContent = 'baseline ' + fmtNum(spec.baseline); }
  for (const s of spec.series) { let d = '';
    s.pts.forEach((p, i) => { const x = X(p[0]), y = Y(p[1]);
      d += i === 0 ? `M${x},${y}` : spec.kind === 'step' ? `H${x}V${y}` : `L${x},${y}`; });
    el('path', {d, fill: 'none', stroke: s.color, 'stroke-width': 2, 'stroke-linejoin': 'round', 'stroke-linecap': 'round'}, svg);
    if (spec.kind !== 'step') for (const p of s.pts)
      el('circle', {cx: X(p[0]), cy: Y(p[1]), r: 4, fill: s.color, stroke: 'var(--surface)', 'stroke-width': 2}, svg);
    const last = s.pts[s.pts.length - 1];
    el('text', {x: X(last[0]) - 4, y: Y(last[1]) - 6, 'text-anchor': 'end', style: 'fill:var(--ink-2)'}, svg).textContent = fmtNum(last[1]); }
  const cross = el('line', {y1: m.t, y2: H - m.b, stroke: 'var(--axis)', 'stroke-width': 1, visibility: 'hidden'}, svg);
  const t = tip(box); const times = [...new Set(pts.map(p => p[0]))].sort((a, b) => a - b);
  svg.addEventListener('pointermove', e => { const r = svg.getBoundingClientRect(), px = e.clientX - r.left;
    let best = times[0]; for (const tt of times) if (Math.abs(X(tt) - px) < Math.abs(X(best) - px)) best = tt;
    cross.setAttribute('x1', X(best)); cross.setAttribute('x2', X(best)); cross.setAttribute('visibility', 'visible');
    const rows = [{text: fmtTime(best)}];
    for (const s of spec.series) { let v = null, c = null;
      s.pts.forEach((p, i) => { if (p[0] <= best) { v = p[1]; c = s.commits ? s.commits[i] : null; } });
      if (v !== null) rows.push({color: s.color, value: fmtNum(v) + (spec.unit ? ' ' + spec.unit : ''), text: s.name + (c ? ' @ ' + c.slice(0, 8) : '')}); }
    if (spec.baseline != null) rows.push({value: fmtNum(spec.baseline), text: 'baseline'});
    showTip(t, box, X(best), e.clientY - r.top, rows); });
  svg.addEventListener('pointerleave', () => { cross.setAttribute('visibility', 'hidden'); t.style.display = 'none'; });
}

function timeline(box, spec) {
  const lane = 30, labelW = Math.min(220, box.clientWidth * 0.3), m = {r: 12, t: 4, b: 24};
  const W = box.clientWidth, H = m.t + spec.lanes.length * lane + m.b;
  const x0 = spec.from, x1 = Math.max(spec.to, spec.from + 3600);
  const X = t => labelW + (t - x0) / (x1 - x0) * (W - labelW - m.r);
  const svg = el('svg', {width: W, height: H, role: 'img'}, box); const t = tip(box);
  const hover = (node, rows) => { node.style.cursor = 'default';
    node.addEventListener('pointermove', e => { const r = box.getBoundingClientRect();
      showTip(t, box, e.clientX - r.left, e.clientY - r.top, rows); });
    node.addEventListener('pointerleave', () => { t.style.display = 'none'; }); };
  for (const tk of timeTicks(x0, x1, W - labelW - m.r)) {
    el('line', {x1: X(tk.t), x2: X(tk.t), y1: m.t, y2: H - m.b, stroke: 'var(--grid)', 'stroke-width': 1}, svg);
    el('text', {x: X(tk.t), y: H - 6, 'text-anchor': 'middle'}, svg).textContent = tk.label; }
  spec.lanes.forEach((ln, i) => { const cy = m.t + i * lane + lane / 2;
    const label = el('text', {x: 0, y: cy + 4, style: 'fill:var(--ink);font-size:13px'}, svg);
    label.textContent = ln.name.length > 30 ? ln.name.slice(0, 29) + '…' : ln.name;
    if (ln.href) { label.style.cursor = 'pointer'; label.addEventListener('click', () => { location.href = ln.href; }); }
    for (const s of ln.spans) { const x = X(s.from), w = Math.max(4, X(s.to) - x);
      const bar = el('rect', {x, y: cy - 6, width: w, height: 12, rx: 4,
        fill: s.status === 'active' ? 'var(--series-1)' : s.status === 'done' ? 'var(--series-1-wash)' : 'var(--grid)'}, svg);
      hover(bar, [{text: ln.name}, {text: fmtTime(s.from) + ' → ' + (s.status === 'active' ? 'now' : fmtTime(s.to) + ' (' + s.status + ')')}]); }
    for (const mk of ln.marks) { const x = X(mk.t); let node;
      if (mk.kind === 'goal' || mk.kind === 'steer') node = el('path', {d: `M${x},${cy - 6}L${x + 6},${cy}L${x},${cy + 6}L${x - 6},${cy}Z`,
        fill: 'var(--accent-2)', stroke: 'var(--surface)', 'stroke-width': 2}, svg);
      else node = el('circle', {cx: x, cy, r: 4, fill: 'var(--good)', stroke: 'var(--surface)', 'stroke-width': 2}, svg);
      const hit = el('circle', {cx: x, cy, r: 12, fill: 'transparent'}, svg);
      hover(hit, [{text: fmtTime(mk.t)}, {text: mk.label}]); } });
  const now = X(spec.to); el('line', {x1: now, x2: now, y1: m.t, y2: H - m.b, stroke: 'var(--ink-2)', 'stroke-width': 1}, svg);
}

function draw() { for (const box of document.querySelectorAll('.chart')) {
  const spec = JSON.parse(box.nextElementSibling.textContent); box.replaceChildren();
  if (box.dataset.spec === 'timeline') timeline(box, spec); else lineChart(box, spec); } }
draw(); let rt; addEventListener('resize', () => { clearTimeout(rt); rt = setTimeout(draw, 150); });

// Reload when the log changes, keeping the scroll position.
const live = document.querySelector('.live'); const seen = live && live.dataset.stamp;
if (seen) setInterval(async () => { try { const r = await fetch('/api/stamp', {cache: 'no-store'});
  const s = await r.text(); live.classList.remove('stale');
  if (s !== seen) { sessionStorage.setItem('y', scrollY); location.reload(); } }
  catch { live.classList.add('stale'); } }, 5000);
const y = sessionStorage.getItem('y'); if (y) { sessionStorage.removeItem('y'); scrollTo(0, +y); }
})();
