// A: the user's open steps from the do_now view, in the sprint's order. The
// first one shown is next. Numbers are the sprint's, so a subgoal's view
// matches the whole-sprint view.
const items = rows('A');
// Shown before the fold. Six fits the panel and the usual run of steps with commands.
const SHOWN = 6;
const card = (it, n) => `<div class="todo${n === 0 ? ' next' : ''}"><div class="num">${it.rank}</div><div>`
  + `<div class="t">${inl(it.title)}</div><div class="meta">${pill(it.status)}`
  + `<span class="chip">${esc(it.stage || 'Sprint-wide')}</span>` + '</div>'
  + (it.note ? `<div class="note">${inl(it.note)}</div>` : '') + '</div></div>';
const filtered = items.length && Number(items[0].filtered);
let h = '<h2>Do now (you)</h2>'
  + (filtered ? `<p class="mut sm">${items.length} of the sprint's ${items[0].total} steps: this stage's and the sprint-wide ones.</p>` : '');
if (!items.length) {
  h += '<p class="mut">Nothing for you to do now.</p>';
} else {
  const cards = items.map(card);
  h += cards.slice(0, SHOWN).join('');
  if (cards.length > SHOWN) {
    h += `<details class="more"><summary>${cards.length - SHOWN} more steps for you, later in the plan</summary>${cards.slice(SHOWN).join('')}</details>`;
  }
}
render(h);
