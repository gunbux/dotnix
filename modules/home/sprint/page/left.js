// A: the stages in view. B: open steps in view, in plan order.
// C: the stages' context sections. Active stages, and the one in view, are open.
const st = rows('A');
const items = rows('B');
const cx = rows('C');
const table = (open) => '<table class="steps">' + (open.map((i) =>
  `<tr><td class="mut">#${esc(i.item)}</td><td>${inl(i.title)}`
  + (i.note ? `<div class="note">${inl(i.note)}</div>` : '')
  + `</td><td><span class="chip${i.owner === 'user' ? ' you' : ''}">${i.owner === 'user' ? 'you' : 'agent'}</span></td>`
  + `<td>${pill(i.status)}</td></tr>`).join('') || '<tr><td colspan="4" class="mut">No open steps.</td></tr>') + '</table>';
let h = "<h2>What's left, by stage</h2>";
for (const g of st) {
  const open = items.filter((i) => i.subgoal === g.key);
  h += `<details class="stage-d"${g.status === 'active' || g.key === view ? ' open' : ''}>`
    + `<summary><b>${esc(g.title)}</b> ${pill(g.status)} <span class="mut sm">${open.length} open`
    + (g.key === view ? '' : ` · <a href="${viewLink(g.key)}">open this stage</a>`) + '</span></summary>'
    + `<p class="goal">${inl(g.goal)}</p>${table(open)}${ctxHtml(cx.filter((c) => c.subgoal === g.key), false)}</details>`;
}
const loose = items.filter((i) => !i.subgoal);
if (loose.length) {
  h += `<details class="stage-d" open><summary><b>Not in a stage</b> <span class="mut sm">${loose.length} open</span></summary>${table(loose)}</details>`;
}
if (!st.length && !loose.length) h += '<p class="mut">Nothing left.</p>';
render(h);
