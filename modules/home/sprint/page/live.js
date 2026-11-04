// Cards never fold: their rows do, then fit.js fades the bottom of the row.
// A: live items for this view (`sprint live`, `sprint poll`), live ones
// first. Times are unix seconds. Ages use this browser's clock, so an item
// whose poller died shows as stale. Clock times are SGT.
const items = rows('A');
const nowS = Date.now() / 1000;
const sgt = (t) => new Date(Number(t) * 1000).toLocaleTimeString('en-GB',
  { timeZone: 'Asia/Singapore', hour: '2-digit', minute: '2-digit' });
const span = (s) => {
  s = Math.abs(Math.round(s));
  if (s < 120) return `${s} s`;
  const m = Math.round(s / 60);
  if (m < 120) return `${m} min`;
  const h = Math.floor(m / 60);
  return h < 48 ? `${h} h ${String(m % 60).padStart(2, '0')} min` : `${Math.round(h / 24)} days`;
};
const card = (r) => {
  const done = r.state === 'done';
  const stale = !done && r.stale_after != null && nowS - Number(r.seen_at) > Number(r.stale_after);
  const title = r.link ? `<a href="${esc(r.link)}" target="_blank">${esc(r.title)}</a>` : esc(r.title);
  const where = view === '-' && r.subgoal ? `<span class="chip">${esc(r.subgoal)}</span>` : '';
  const tag = done ? pill('done') : stale ? '<span class="pill p-stale">stale</span>' : '<span class="pill p-doing">live</span>';
  let h = `<div class="lv${done ? ' lv-done' : ''}${stale ? ' lv-stale' : ''}">`
    + `<div class="sh"><b>${title}</b><span class="lv-tags">${where}${tag}</span></div>`
    + `<div class="mut sm">${done ? `done ${span(nowS - Number(r.done_at))} ago` : `updated ${span(nowS - Number(r.updated_at))} ago`}`
    + (stale ? `, no update for ${span(nowS - Number(r.seen_at))}` : '') + '</div>';
  if (r.total_n != null) {
    const pct = 100 * Number(r.done_n || 0) / Number(r.total_n);
    h += `${bar(pct)}<div class="sm">${esc(r.done_n || 0)} of ${esc(r.total_n)}</div>`;
  }
  if (r.ends_at != null && !done) {
    const left = Number(r.ends_at) - nowS;
    h += `<div class="sm${left < 0 ? ' warn' : ''}">ends ${sgt(r.ends_at)} SGT `
      + (left >= 0 ? `(in ${span(left)})` : `(${span(left)} late)`) + '</div>';
  }
  if (r.error) h += `<div class="sm bad">Last update failed ${span(nowS - Number(r.seen_at))} ago: ${esc(r.error)}</div>`;
  if (r.body) {
    // JSON in the body means the poller's output didn't parse as a result.
    const raw = /^\s*\{\s*"/.test(String(r.body));
    h += `<div class="lv-body${raw ? ' lv-raw' : ''}">${mdFit(r.body)}</div>`;
  }
  return h + '</div>';
};
render('<h2>Live</h2>' + (items.length
  ? `<div class="lv-grid">${items.map(card).join('')}</div>`
  : '<p class="mut">Nothing in flight. <code>sprint live set</code> or <code>sprint poll</code> adds a card here.</p>'));
