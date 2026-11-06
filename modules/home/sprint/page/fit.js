// Business Text runs this after each render (afterRender), with
// context.element holding the section's HTML. Grafana gives every panel a
// fixed height, but the data decides how tall a section is. So this script
// fits the section into its panel, and the panel never scrolls on its own:
//
// 1. While the content is too tall, hide items marked `.fit` (a Do now
//    step, a table row, a card) from the end: rows before cards, and the
//    longest table first. Each table or list keeps its first item.
// 2. If it still doesn't fit, cut the content with a fade.
// 3. Show "Show all (N more)" at the bottom. An item with data-fit-kind
//    (such as "merge-ready PR") is counted by kind, in bold, in its "⋯ N more"
//    marker and in the bar, so a fold never hides an action without saying so. It shows everything and lets
//    the panel scroll; "Fold to fit" goes back.
//
// Opening a closed list (a <details>, such as Merged or Waiting) means the
// reader wants all of it: the panel shows everything and scrolls, like Show
// all, and "Fold to fit" closes the list again. Opened lists stay open when
// Grafana renders the panel again on a refresh.
//
// A table wider than its box gets class `tight`, which breaks words anywhere.
//
// It writes what it did on context.element as data-sp-* attributes, and
// `sprint dash check` reads them from a headless browser.
const el = context.element;
const root = el && el.querySelector('.sp');
if (!root) return;
const self = this;
// The element that scrolls: the nearest parent whose overflow is not visible.
let box = el.parentElement;
for (let p = el; p && p !== document.body; p = p.parentElement) {
  if (/(auto|scroll|hidden)/.test(getComputedStyle(p).overflowY)) { box = p; break; }
}
const over = () => box.scrollHeight - box.clientHeight;

// Lists the reader opened, by summary text without numbers, so a count that
// changes on refresh keeps the list open. Kept on `this`, which outlives a
// render.
const listKey = (d) => {
  const s = d.querySelector(':scope > summary');
  return s ? s.textContent.replace(/\d+/g, '').replace(/\s+/g, ' ').trim() : '';
};
self.opened = self.opened || new Set();
// `?sp-open=1` opens every list, for `sprint dash check --open`.
const openAll = new URLSearchParams(location.search).get('sp-open') === '1';
root.querySelectorAll('details').forEach((d) => {
  if (d.open) d.dataset.fitInit = '';
  else if (openAll || self.opened.has(listKey(d))) { d.dataset.fitUser = ''; d.open = true; }
});
const userOpen = () => root.querySelector('details[open][data-fit-user]') !== null;

const fit = () => {
  root.querySelectorAll('.fit-hide').forEach((n) => n.classList.remove('fit-hide'));
  root.querySelectorAll('.fit-more').forEach((n) => n.remove());
  root.classList.remove('fit-clip');
  root.style.maxHeight = '';
  const old = root.querySelector('.fit-bar');
  if (old) old.remove();
  box.style.overflowY = '';
  // A table wider than its box may break words anywhere. Only then: at a
  // normal width, short words stay whole.
  root.querySelectorAll('table.tight').forEach((t) => t.classList.remove('tight'));
  root.querySelectorAll('table').forEach((t) => {
    if (t.offsetParent !== null && t.scrollWidth > t.parentElement.clientWidth + 1) t.classList.add('tight');
  });

  let hidden = 0;
  const kinds = new Map(); // data-fit-kind -> hidden count
  const kindText = (m) => [...m].map(([k, n]) => `${n} ${k}${n > 1 ? 's' : ''}`).join(', ');
  let state = 'ok';
  if (self.showAll || userOpen()) {
    state = 'all';
  } else if (over() > 1) {
    // Measure with a bar of the real size in place.
    const bar = document.createElement('button');
    bar.className = 'fit-bar';
    bar.textContent = 'Show all (99 more)';
    root.appendChild(bar);
    // A folded table or list ends in a "⋯ N more" marker, so a reader
    // knows rows are missing there. Rows of cards need none: the bar says it.
    const marks = new Map();
    const hide = (it) => {
      it.classList.add('fit-hide');
      hidden++;
      const kind = it.dataset.fitKind;
      if (kind) kinds.set(kind, (kinds.get(kind) || 0) + 1);
      const g = it.parentElement;
      if (/^(grid|flex)$/.test(getComputedStyle(g).display)) return;
      if (!marks.has(g)) {
        const tag = it.tagName === 'TR' ? 'tr' : it.tagName === 'LI' ? 'li' : 'div';
        const m = document.createElement(tag);
        m.className = 'fit-more';
        // As many columns as the row it follows: a larger colspan adds
        // columns, and a fixed-layout table then squeezes every column.
        if (tag === 'tr') m.appendChild(document.createElement('td')).colSpan =
          Array.from(it.cells).reduce((n, c) => n + c.colSpan, 0);
        g.appendChild(m);
        marks.set(g, { m, n: 0, kinds: new Map() });
      }
      const k = marks.get(g);
      k.n++;
      if (kind) k.kinds.set(kind, (k.kinds.get(kind) || 0) + 1);
      k.m.classList.toggle('fit-more-kind', k.kinds.size > 0);
      (k.m.firstChild && k.m.firstChild.nodeType === 1 ? k.m.firstChild : k.m).textContent =
        k.kinds.size ? `⋯ ${kindText(k.kinds)} hidden` + (k.n > [...k.kinds.values()].reduce((a, b) => a + b, 0)
          ? `, ${k.n - [...k.kinds.values()].reduce((a, b) => a + b, 0)} more` : '') : `⋯ ${k.n} more`;
    };
    // Items are grouped by their parent: the rows of one table, the cards
    // of one grid. Deeper groups fold first, so cards lose rows before a
    // card goes. Within a depth, the group with the most items shown loses
    // its last one, so every table keeps its first rows.
    const groups = new Map();
    for (const it of root.querySelectorAll('.fit')) {
      if (!groups.has(it.parentElement)) groups.set(it.parentElement, []);
      groups.get(it.parentElement).push(it);
    }
    const depth = (n) => { let d = 0; for (; n && n !== root; n = n.parentElement) d++; return d; };
    const shown = (g) => g.filter((it) => !it.classList.contains('fit-hide') && it.offsetParent !== null);
    const byDepth = [...groups.values()].sort((a, b) => depth(b[0]) - depth(a[0]));
    const levels = [...new Set(byDepth.map((g) => depth(g[0])))];
    // Every group keeps its first item: an empty table reads as broken.
    for (const d of levels) {
      while (over() > 1) {
        const cands = byDepth.filter((g) => depth(g[0]) === d && shown(g).length > 1);
        if (!cands.length) break;
        const g = cands.reduce((a, b) => (shown(b).length >= shown(a).length ? b : a));
        const vis = shown(g);
        hide(vis[vis.length - 1]);
      }
    }
    // One marker in the whole panel only repeats the bar's count, unless it
    // names kinds: then it shows where they are.
    if (marks.size === 1 && hidden === [...marks.values()][0].n && !kinds.size) [...marks.values()][0].m.remove();
    state = 'folded';
    if (over() > 1) {
      // One item is taller than the panel: cut it and fade the cut edge.
      root.classList.add('fit-clip');
      root.style.maxHeight = Math.max(40, box.clientHeight - bar.offsetHeight - 8) + 'px';
      state = 'clipped';
    }
    bar.remove();
  }
  if (state !== 'ok') {
    const bar = document.createElement('button');
    bar.type = 'button';
    bar.className = 'fit-bar';
    bar.textContent = state === 'all' ? 'Fold to fit'
      : 'Show all' + (hidden ? ` (${hidden} more${kinds.size ? ': ' + kindText(kinds) : ''})` : '');
    bar.classList.toggle('fit-bar-kind', state !== 'all' && kinds.size > 0);
    bar.onclick = () => {
      if (state === 'all') {
        // Fold to fit: also close the lists the reader opened.
        self.showAll = false;
        self.opened.clear();
        root.querySelectorAll('details[open][data-fit-user]').forEach((d) => {
          delete d.dataset.fitUser;
          d.open = false;
        });
      } else {
        self.showAll = true;
      }
      fit();
    };
    // Outside the clipped root, so the cut never hides it.
    (state === 'clipped' ? el : root).appendChild(bar);
  }
  // Fitted content never scrolls, even by a rounding pixel.
  box.style.overflowY = state === 'all' ? 'auto' : 'hidden';

  // How far content spills out of its box sideways, such as a wide table
  // out of a card. A box that scrolls sideways (pre) doesn't count.
  let wide = 0;
  let wideAt = '';
  for (const n of Array.from(root.querySelectorAll('*')).concat(root)) {
    const d = n.scrollWidth - n.clientWidth;
    if (d > wide && getComputedStyle(n).overflowX === 'visible') {
      wide = d;
      wideAt = n.tagName.toLowerCase() + (n.className ? '.' + String(n.className).trim().split(/\s+/).join('.') : '');
      wideAt += ' "' + n.textContent.trim().replace(/\s+/g, ' ').slice(0, 40) + '"';
    }
  }
  const used = el.getBoundingClientRect().bottom - box.getBoundingClientRect().top;
  el.dataset.spPanel = (root.className.match(/sp-p-([\w-]+)/) || [])[1] || '';
  el.dataset.spFit = state;
  el.dataset.spHidden = String(hidden);
  el.dataset.spHiddenKinds = kindText(kinds);
  el.dataset.spGap = String(Math.max(0, Math.round(box.clientHeight - used)));
  el.dataset.spWide = String(Math.max(0, Math.round(wide)));
  el.dataset.spRaw = String(root.querySelectorAll('.lv-raw').length);
  el.dataset.spWideAt = wideAt;
  // Content cut with no way to see it: taller than the panel, and the panel
  // doesn't scroll. Fitted states never leave this; it catches a missed case.
  el.dataset.spCut = String(over() > 1 && !/(auto|scroll)/.test(getComputedStyle(box).overflowY) ? Math.round(over()) : 0);
  el.dataset.spOpen = String(root.querySelectorAll('details[open][data-fit-user]').length);
};

// Opening or closing a list changes the height, so fit again. The toggle
// event doesn't bubble, so listen in the capture phase.
const onToggle = (e) => {
  const d = e.target;
  if (!(d instanceof HTMLDetailsElement) || !root.contains(d)) return;
  // Lists the page rendered open fire a toggle too: not the reader's doing.
  if (d.open && 'fitInit' in d.dataset && !('fitClosed' in d.dataset)) return;
  if (!d.open) {
    d.dataset.fitClosed = '';
    delete d.dataset.fitUser;
    self.opened.delete(listKey(d));
  } else if (!('fitInit' in d.dataset) || 'fitClosed' in d.dataset) {
    d.dataset.fitUser = '';
    self.opened.add(listKey(d));
  }
  fit();
  if (d.open) {
    // Bring the opened list into view inside the panel, not the page.
    const r = d.getBoundingClientRect();
    const b = box.getBoundingClientRect();
    if (r.bottom > b.bottom) box.scrollTop += Math.min(r.top - b.top, r.bottom - b.bottom);
  }
};
root.addEventListener('toggle', onToggle, true);

fit();
// Fit again when the panel or the window changes size.
let last = box.clientWidth + 'x' + box.clientHeight;
const ro = new ResizeObserver(() => {
  const now = box.clientWidth + 'x' + box.clientHeight;
  if (now !== last) { last = now; fit(); }
});
ro.observe(box);
return () => { ro.disconnect(); root.removeEventListener('toggle', onToggle, true); };
