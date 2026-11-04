// A: the user's open steps in plan order. The first one is next.
const items = rows('A');
const card = (it, n) => `<div class="todo${n === 0 ? ' next' : ''}"><div class="num">${n + 1}</div><div>`
  + `<div class="t">${inl(it.title)}</div><div class="meta">${pill(it.status)}`
  + (it.stage ? `<span class="chip">${esc(it.stage)}</span>` : '') + '</div>'
  + (it.note ? `<div class="note">${inl(it.note)}</div>` : '') + '</div></div>';
let h = '<h2>Do now (you)</h2>';
if (!items.length) {
  h += '<p class="mut">Nothing for you to do now.</p>';
} else {
  const cards = items.map(card);
  h += cards.slice(0, 5).join('');
  if (cards.length > 5) {
    h += `<details class="more"><summary>${cards.length - 5} more steps for you, later in the plan</summary>${cards.slice(5).join('')}</details>`;
  }
}
render(h);
