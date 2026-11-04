// A: percent, done and in_scope for the view.
const p = rows('A')[0];
render(p ? `<div class="progress"><div class="big">${esc(p.percent)}%</div>${bar(p.percent)}`
  + `<div class="mut sm">${esc(p.done)} of ${esc(p.in_scope)} steps done${view === '-' ? '' : ' in this stage'}</div></div>` : '');
