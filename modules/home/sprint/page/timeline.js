// A: the timeline view's steps in this view: the user's open steps, with
// their state and Do now number, and the done steps a needs link touches.
// Each step needs at most one other, so the links form trees. Each tree is
// one track, read left to right: its last two done steps, then its open
// steps. A lone waiting or later step is a track of its own, and such
// tracks share a row. A lone ready step is only in Do now.
const steps = rows('A');
const byItem = new Map(steps.map((s) => [Number(s.item), s]));
const parent = (s) => (s.needs != null && byItem.has(Number(s.needs)) ? Number(s.needs) : null);
const kids = new Map();
steps.forEach((s) => {
  const p = parent(s);
  if (p != null) kids.set(p, (kids.get(p) || []).concat(s));
});
const order = { ready: 0, waiting: 1, later: 2 };
const walk = (s, out) => {
  out.push(s);
  (kids.get(Number(s.item)) || []).forEach((k) => walk(k, out));
  return out;
};
const chains = steps.filter((s) => parent(s) == null).map((root) => walk(root, []))
  .map((nodes) => ({ nodes, open: nodes.filter((s) => s.state !== 'done') }))
  .filter((c) => c.open.length && !(c.nodes.length === 1 && c.open[0].state === 'ready'))
  // Within a state, longer chains first, so the one-step tracks pack into rows.
  .sort((a, b) => order[a.open[0].state] - order[b.open[0].state]
    || (a.nodes.length === 1) - (b.nodes.length === 1) || a.open[0].rank - b.open[0].rank);

const sgt = (t) => new Date(Number(t) * 1000).toLocaleString('en-GB',
  { weekday: 'short', hour: '2-digit', minute: '2-digit', hour12: false, timeZone: 'Asia/Singapore' }).replace(',', '');
const ago = (t) => {
  const m = Math.max(0, (Date.now() / 1000 - Number(t)) / 60);
  return m < 60 ? `${Math.round(m)}m` : m < 2880 ? `${Math.round(m / 60)}h` : `${Math.round(m / 1440)}d`;
};
// A needed step that is open has a Do now number; any other has its item number.
const after = (s) => {
  const n = byItem.get(Number(s.needs));
  return n && n.rank != null ? `step ${n.rank}` : `#${s.needs}`;
};
const needsOpen = (s) => s.needs != null && (!byItem.has(Number(s.needs)) || byItem.get(Number(s.needs)).state !== 'done');
// Why the step can't be done yet, then when and after what.
const meta = (s) => {
  switch (s.state) {
    case 'done': return `<div class="tl-m">done ${sgt(s.at)}</div>`;
    case 'ready': return '<div class="tl-m"><b>now</b> · in Do now</div>';
    case 'later': return `<div class="tl-m">after ${after(s)}</div>`;
  }
  const why = s.waits_on ? `waiting on ${inl(s.waits_on)}` : s.note ? `blocked: ${inl(s.note)}` : 'blocked';
  const when = [s.at != null && `since ${ago(s.at)}`, needsOpen(s) && `after ${after(s)}`].filter(Boolean).join(' · ');
  return `<div class="tl-m tl-why">${why}</div>` + (when ? `<div class="tl-m">${when}</div>` : '');
};
const node = (s) => `<li class="tl-n tl-${esc(s.state)}"><div class="tl-rail"><span class="tl-dot">`
  + `${s.state === 'done' ? '✓' : esc(s.rank)}</span></div>`
  + `<div class="tl-t" title="${esc(s.title)}">${inl(s.title)}</div>${meta(s)}</li>`;
const track = (c) => {
  const done = c.nodes.filter((s) => s.state === 'done');
  const earlier = done.length - 2;
  return `<div class="tl-chain fit${c.nodes.length === 1 ? ' tl-one' : ''}"><div class="tl-lab"><span class="chip">${esc(c.open[0].stage || 'Sprint-wide')}</span></div>`
    + '<ol class="tl-track">'
    + (earlier > 0 ? `<li class="tl-n tl-more"><div class="tl-rail"><span class="tl-dot">⋯</span></div>`
      + `<div class="tl-m">${earlier} done before</div></li>` : '')
    + done.slice(-2).concat(c.open).map(node).join('') + '</ol></div>';
};
const key = (cls, text) => `<span><span class="sw tl-sw-${cls}"></span>${text}</span>`;
render('<div class="sh"><h2>Timeline</h2><div class="legend">'
  + key('ready', 'now') + key('waiting', 'waiting on someone') + key('later', 'after an earlier step') + key('done', 'done')
  + '</div></div>'
  + (chains.length ? '<div class="tl">' + chains.map(track).join('') + '</div>'
    : '<p class="mut">No step of yours waits on someone or on an earlier step.</p>'));
