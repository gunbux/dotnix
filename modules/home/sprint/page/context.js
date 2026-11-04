// A: the whole sprint's context sections. The first one is open.
const cx = rows('A');
render('<h2>Whole sprint</h2>' + (cx.length ? ctxHtml(cx, true) : '<p class="mut">No context sections yet.</p>'));
