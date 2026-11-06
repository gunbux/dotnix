// A: the user's open steps from the do_now view, in the sprint's order. The
// first one shown is next. Numbers are the sprint's, so a subgoal's view
// matches the whole-sprint view. B: the user's open steps that this view's
// filter hides (other stages), so the view can say they exist.
const items = rows('A');
const away = rows('B')[0] || {};
// ./fit.js folds the steps that don't fit the panel.
// data-fit-kind lets ./fit.js name what a fold hides.
const card = (it, n) => `<div class="todo fit${n === 0 ? ' next' : ''}" data-fit-kind="${it.status === 'blocked' ? 'blocked step' : 'open step'}"><div class="num">${it.rank}</div><div>`
  + `<div class="t">${inl(it.title)}</div><div class="meta">${pill(it.status)}`
  + `<span class="chip">${esc(it.stage || 'Sprint-wide')}</span>` + '</div>'
  + (it.note ? `<div class="note">${inl(it.note)}</div>` : '') + '</div></div>';
const filtered = items.length && Number(items[0].filtered);
let h = '<h2>Do now (you)</h2>'
  + (filtered ? `<p class="mut sm">${items.length} of the sprint's ${items[0].total} steps: this stage's and the sprint-wide ones.</p>` : '')
  + (Number(away.n) ? `<p class="elsewhere"><b>+${away.n} step${away.n > 1 ? 's' : ''} in other stages</b>`
    + ` (${away.ready} open, ${away.n - away.ready} blocked)`
    + ` · <a href="${viewLink('-')}">Whole sprint</a></p>` : '');
if (!items.length) {
  h += '<p class="mut">Nothing for you to do now.</p>';
} else {
  h += items.map(card).join('');
}
render(h);
