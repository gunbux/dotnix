// A: every stage (subgoal) with its progress, active first, done last.
// A card opens that stage's view.
const st = rows('A');
render('<h2>Stages</h2>' + (st.length
  ? '<div class="stages">' + st.map((g) =>
    `<a class="stage fit s-${esc(g.status)}${g.key === view ? ' sel' : ''}" href="${viewLink(g.key)}">`
    + `<div class="sh"><b>${esc(g.title)}</b>${pill(g.status)}</div>${bar(g.percent)}`
    + `<div class="mut sm">${esc(g.done)} of ${esc(g.in_scope)} steps done</div>`
    + `<div class="dw"><span class="lab">Done when</span> ${inl(g.done_when || '')}</div></a>`).join('') + '</div>'
  : '<p class="mut">No stages yet.</p>'));
