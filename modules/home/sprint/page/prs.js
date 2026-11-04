// The PR board, from the sprint log. A: the view's open PRs with their last
// board row from `sprint pr sync` (grp, steps, rank: see pkgs/sprint/prboard.go),
// the user's note, and PRs merged in the last 3 days. B: the last sync.
// Clock times are SGT.
const prs = rows('A');
const synced = rows('B')[0];
const nowS = Date.now() / 1000;
const GROUPS = [
  ['merge', 'Merge now', '&#10003;', 'Every review bot scores 5/5 on the newest commit, CI is green, and no PR comes first. The numbers give the review order.'],
  ['fix', 'Fix first', '&#10007;', 'Something blocks the merge. The next step says what to do.'],
  ['wait', 'Waiting', '&#8230;', 'Nothing for you yet. Each one waits on a draft, a stacked base, a bot, or CI.'],
];
const list = (s) => { try { return JSON.parse(s || '[]'); } catch (e) { return []; } };
const chip = (kind, text) => `<span class="gc ${kind}">${{ ok: '&#10003;', bad: '&#10007;', wait: '&#8230;' }[kind]} ${esc(text)}</span>`;
const sgtDay = (t) => new Date(Number(t) * 1000).toLocaleString('en-GB', { timeZone: 'Asia/Singapore',
  weekday: 'short', day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });
const sgtTime = (t) => new Date(Number(t) * 1000).toLocaleTimeString('en-GB',
  { timeZone: 'Asia/Singapore', hour: '2-digit', minute: '2-digit' });
const num = (p) => (p.number ? `#${p.number}` : `#${String(p.url).split('/').pop()}`);

// merged: a missing or old score counts against the PR, as it merged so.
const gate = (p, merged) => {
  const bots = list(p.bots);
  const out = bots.map((b) => (b.score < 0 ? chip(merged ? 'bad' : 'wait', `${b.name}: no score`)
    : !b.on_head ? chip(merged ? 'bad' : 'wait', `${b.name} ${b.score}/5, older commit`)
    : chip(b.score === 5 ? 'ok' : 'bad', `${b.name} ${b.score}/5`)));
  if (!bots.length) out.push(chip(merged ? 'bad' : 'wait', 'no review bot'));
  if (!merged) {
    const failing = list(p.failing);
    out.push(failing.length ? chip('bad', `CI: ${failing.length} failing`)
      : Number(p.running) ? chip('wait', `CI: ${p.running} running`) : chip('ok', 'CI'));
  }
  out.push(chip(Number(p.threads) ? 'bad' : 'ok', `${p.threads || 0} open threads`));
  if (Number(p.draft) && !merged) out.push(chip('wait', 'draft'));
  return out.join('');
};

const open = prs.filter((p) => p.state !== 'merged').map((p) => (p.grp ? p
  : { ...p, grp: 'wait', steps: JSON.stringify(['Not synced yet. Run `sprint pr sync`.']) }));
const merged = prs.filter((p) => p.state === 'merged');

let h = '<h2>PRs: what to do</h2>';
if (synced && synced.at) {
  const age = Math.round((nowS - Number(synced.at)) / 60);
  h += `<p class="sm ${age > 15 ? 'warn' : 'mut'}">GitHub data from ${sgtTime(synced.at)} SGT, ${age} min ago`
    + (age > 15 ? '. Run <code>sprint pr sync</code>, or start a poller for it.' : '.') + '</p>';
}
h += '<div class="prb"><div class="prb-tiles">'
  + GROUPS.map(([k, name]) => `<div class="prb-tile g-${k}"><b>${open.filter((p) => p.grp === k).length}</b>${name}</div>`).join('')
  + '</div>';
for (const [k, name, mark, desc] of GROUPS) {
  const g = open.filter((p) => p.grp === k);
  if (!g.length) continue;
  const head = `<h3 class="g-${k}">${mark} ${name} (${g.length}) <span class="d">${desc}</span></h3>`;
  // Waiting needs nothing from the reader, so it starts folded.
  h += k === 'wait' ? `<details class="prb-fold"><summary>${head}</summary>` : head;
  h += `<table class="g-${k}"><tr><th>${k === 'wait' ? 'PR' : 'Order and PR'}</th><th>What it does</th><th>Gate</th><th>Next step</th></tr>`;
  g.forEach((p, i) => {
    let steps = list(p.steps);
    if (k === 'merge') {
      if (p.note && p.note.startsWith('First,')) steps = [p.note, ...(steps.length ? steps : ['Then merge.'])];
      else steps = [...(steps.length ? steps : ['Merge.']), ...(p.note ? [p.note] : [])];
    } else if (p.note) {
      steps.push(p.note);
    }
    const meta = [p.stage || 'whole sprint', p.base && p.base !== 'main' ? `base ${p.base}` : ''].filter(Boolean).join(' · ');
    h += `<tr><td class="n">${k === 'wait' ? '' : `<span class="rk">${i + 1}</span>`}`
      + `<a href="${esc(p.url)}" target="_blank">${esc(num(p))}</a>`
      + (p.stack ? `<div class="stack">${esc(p.stack)}</div>` : '')
      + (k === 'wait' || !p.why ? '' : `<div class="stack">${esc(p.why)}</div>`) + '</td>'
      + `<td><div class="t">${esc(p.title)}</div><div class="note">${esc(meta)}</div></td>`
      + `<td class="gate">${p.number ? gate(p, false) : ''}</td>`
      + `<td class="why"><ul>${steps.map((s) => `<li>${inl(s)}</li>`).join('')}</ul></td></tr>`;
  });
  h += '</table>' + (k === 'wait' ? '</details>' : '');
}
if (merged.length) {
  h += `<details class="prb-fold"><summary><h3 class="g-merged">&#8618; Merged in the last 3 days (${merged.length}) `
    + '<span class="d">Newest first. The gate shows the last sync before the merge.</span></h3></summary>'
    + '<table class="g-merged"><tr><th>Merged (SGT)</th><th>PR</th><th>What it does</th><th>Gate at merge</th></tr>'
    + merged.map((p) => `<tr><td class="when">${sgtDay(p.at)}</td><td class="n"><a href="${esc(p.url)}" target="_blank">${esc(num(p))}</a></td>`
      + `<td><div class="t">${esc(p.title)}</div><div class="note">${esc(p.stage || 'whole sprint')}</div></td>`
      + `<td class="gate">${p.grp ? gate(p, true) : '<span class="mut sm">not synced</span>'}</td></tr>`).join('')
    + '</table></details>';
}
if (!open.length) h += '<p class="mut">No open PRs in this view.</p>';
render(h + '</div>');
