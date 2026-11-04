// A: each metric's latest run and baseline. Bars share one scale per suite.
const b = rows('A');
let h = '<h2>Benchmarks: latest run against baseline</h2>';
if (!b.length) {
  render(h + '<p class="mut">No benchmarks yet.</p>');
} else {
  const paired = b.filter((r) => r.change != null);
  const within = paired.filter((r) => r.change <= 5).length;
  const fmt = (v) => (v == null ? '—' : Math.abs(v) >= 100 ? Number(v).toFixed(0) : String(Number(Number(v).toPrecision(3))));
  const cls = (c) => (c == null ? '' : c <= 5 ? 'ok' : c <= 25 ? 'warn' : 'bad');
  h += `<div class="tiles"><div class="tile"><div class="big">${within} of ${paired.length}</div>`
    + '<div class="mut sm">at most 5% worse than baseline</div></div>'
    + '<div class="tile legend"><span><span class="sw" style="background:var(--k)"></span>Latest run</span>'
    + '<span><span class="sw" style="background:var(--b)"></span>Baseline</span><span>Lower is better for times.</span></div></div>';
  h += '<div class="suites">' + [...new Set(b.map((r) => r.suite))].map((s) => {
    const rs = b.filter((r) => r.suite === s);
    const top = Math.max(...rs.map((r) => Math.max(r.latest || 0, r.baseline || 0))) || 1;
    return `<div class="suite"><div class="st">${esc(s)}</div>` + rs.map((r) =>
      `<div class="br"><div class="bl" title="${esc(r.metric)}">${esc(r.metric)}`
      + (view === '-' && r.stage ? ` · ${esc(r.stage)}` : '') + '</div><div class="bt">'
      + `<div class="bk" style="width:${(100 * (r.latest || 0) / top).toFixed(1)}%"></div>`
      + `<div class="bg" style="width:${(100 * (r.baseline || 0) / top).toFixed(1)}%"></div></div>`
      + `<div class="bv">${fmt(r.latest)} / ${fmt(r.baseline)} ${esc(r.unit)}</div>`
      + `<div class="bc ${cls(r.change)}">${r.change == null ? 'no baseline' : (r.change >= 0 ? '+' : '') + Math.round(r.change) + '%'}</div></div>`).join('') + '</div>';
  }).join('') + '</div>';
  render(h);
}
