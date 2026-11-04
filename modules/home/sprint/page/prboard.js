// A: when the status generator last read GitHub. B: the PR board for this
// view, as HTML. The generator (prs.py beside the static status page) sorts
// open PRs into Merge now, Fix first and Waiting, and renders the board, so
// this panel and the static page show the same board.
const meta = rows('A')[0];
const board = rows('B')[0];
const nowS = Date.now() / 1000;
let h = '<h2>PRs: what to do</h2>';
if (!meta || !board) {
  h += '<p class="mut">No PR data for this sprint. The status generator writes it.</p>';
} else {
  const age = Math.max(0, Math.round((nowS - Number(meta.updated_at)) / 60));
  const at = new Date(Number(meta.updated_at) * 1000).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
  const stale = age > 10;
  h += `<p class="sm ${stale ? 'warn' : 'mut'}">GitHub data from ${at}, ${age} min ago`
    + (stale ? '. The generator has stopped or cannot reach GitHub.' : '. It refreshes every 3 min.') + '</p>'
    + board.html;
}
render(h);
