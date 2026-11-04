// A: the sprint and its goal. B: the subgoal in view, if any.
const s = rows('A')[0];
const g = rows('B')[0];
if (!s) {
  render('<p class="mut">No sprint is selected.</p>');
} else {
  let h = `<div class="mut sm">Sprint · goal v${esc(s.versions)} · goal changed ${when(s.at)}`
    + (g ? ` · <a href="${viewLink('-')}">back to the whole sprint</a>` : '') + '</div>'
    + `<h1>${esc(s.title)}</h1><p class="goal">${inl(s.goal)}</p>`;
  if (g) {
    h += `<div class="viewing"><div class="sh"><span><span class="lab">Viewing stage:</span> <b>${esc(g.title)}</b></span>${pill(g.status)}</div>`
      + `<p class="goal">${inl(g.goal)}</p><div class="dw"><span class="lab">Done when</span> ${inl(g.done_when || '')}</div></div>`;
  }
  render(h);
}
