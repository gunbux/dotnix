// A: the user's open steps from the do_now view, in the sprint's order. Only
// the ready ones get a card: a waiting or later step is on the Timeline
// panel, since there is nothing the user can do about it now. The first
// card is next. Numbers are the sprint's, so a subgoal's view matches the
// whole-sprint view. B: the user's open steps that this view's filter hides
// (other stages), so the view can say they exist.
const items = rows('A');
const away = rows('B')[0] || {};
const ready = items.filter((it) => it.state === 'ready');
const count = (state) => items.filter((it) => it.state === state).length;
const waiting = count('waiting');
const later = count('later');
const steps = (n) => `${n} step${n > 1 ? 's' : ''}`;
// ./fit.js folds the steps that don't fit the panel.
// data-fit-kind lets ./fit.js name what a fold hides.
const card = (it, n) => `<div class="todo fit${n === 0 ? ' next' : ''}" data-fit-kind="open step"><div class="num">${it.rank}</div><div>`
  + `<div class="t">${inl(it.title)}</div><div class="meta">${pill(it.status)}`
  + `<span class="chip">${esc(it.stage || 'Sprint-wide')}</span>` + '</div>'
  + (it.note ? `<div class="note">${inl(it.note)}</div>` : '') + '</div></div>';
const filtered = items.length && Number(items[0].filtered);
let h = '<h2>Do now (you)</h2>'
  + (filtered ? `<p class="mut sm">${items.length} of the sprint's ${items[0].total} steps: this stage's and the sprint-wide ones.</p>` : '')
  + (Number(away.n) ? `<p class="elsewhere"><b>+${steps(away.n)} in other stages</b>`
    + ` (${away.ready} ready, ${away.n - away.ready} waiting or later)`
    + ` · <a href="${viewLink('-')}">Whole sprint</a></p>` : '');
if (!items.length) {
  h += '<p class="mut">Nothing for you to do now.</p>';
} else if (!ready.length) {
  h += '<p class="mut">Nothing you can do now.</p>';
} else {
  // In their own box, so a fold's "⋯ N more" marker comes right after them.
  h += '<div>' + ready.map(card).join('') + '</div>';
}
if (waiting || later) {
  h += '<p class="mut sm">'
    + [waiting && `${steps(waiting)} ${waiting > 1 ? 'wait' : 'waits'} on others`,
      later && `${steps(later)} ${later > 1 ? 'come' : 'comes'} later`].filter(Boolean).join(' · ')
    + ' · Timeline below</p>';
}
render(h);
