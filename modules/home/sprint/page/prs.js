// A: open PRs in view. B: how many merged.
const p = rows('A');
const m = rows('B')[0];
render('<h2>Open PRs</h2><table><tr><th>PR</th><th>Title</th><th>State</th><th>Stage</th></tr>'
  + (p.map((r) => `<tr><td><a href="${esc(r.url)}" target="_blank">#${esc(String(r.url).split('/').pop())}</a></td>`
    + `<td>${esc(r.title)}</td><td>${pill(r.state === 'ready' ? 'ready (5/5)' : 'open')}</td><td class="mut">${esc(r.stage)}</td></tr>`).join('')
    || '<tr><td colspan="4" class="mut">No open PRs.</td></tr>')
  + `</table><p class="mut sm">${m ? esc(m.n) : 0} merged so far.</p>`);
