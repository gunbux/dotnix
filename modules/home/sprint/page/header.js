// A: the sprint and its goal. B: the subgoal in view, if any.
const s = rows('A')[0];
const g = rows('B')[0];
const dev = rv('${dev}');
const devTag = dev ? `<span class="pill p-dev">dev: ${esc(dev)}</span> ` : '';
if (!s) {
  render(`${devTag}<p class="mut">No sprint is selected.</p>`);
} else {
  // A stage's view leads with the stage: its goal and exit check are what
  // the view is about. The sprint stays on the small line above it.
  let h;
  if (g) {
    h = `<div class="mut sm">${devTag}Stage of <b>${esc(s.title)}</b> · <a href="${viewLink('-')}">back to the whole sprint</a></div>`
      + `<div class="sh"><h1>${esc(g.title)}</h1>${pill(g.status)}</div><p class="goal">${inl(g.goal)}</p>`
      + `<div class="dw"><span class="lab">Done when</span> ${inl(g.done_when || '')}</div>`;
  } else {
    h = `<div class="mut sm">${devTag}Sprint · goal v${esc(s.versions)} · goal changed ${when(s.at)}</div>`
      + `<h1>${esc(s.title)}</h1><p class="goal">${inl(s.goal)}</p>`;
  }
  render(h);
}
