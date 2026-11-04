// A: when the generator last wrote the live file, and the runner log's last
// lines. B: benchmark sessions from the last 3 hours, newest first.
// Times are unix seconds. The ages use this browser's clock, so data from a
// stopped generator shows as stale.
const meta = rows('A')[0];
const sessions = rows('B');
const nowS = Date.now() / 1000;
const hm = (t) => (t == null ? '?' : new Date(Number(t) * 1000)
  .toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }));
const zone = new Date().toLocaleTimeString('en-GB', { timeZoneName: 'short' }).split(' ').pop();
const ago = (t) => {
  const s = Math.max(0, Math.round(nowS - Number(t)));
  return s < 120 ? `${s} s` : `${Math.floor(s / 60)} min`;
};
let h = `<h2>Benchmark running now (times ${esc(zone)})</h2>`;
if (!meta) {
  h += '<p class="mut">No live benchmark data for this sprint.</p>';
} else {
  const stale = nowS - Number(meta.updated_at) > 180;
  h += `<p class="sm ${stale ? 'warn' : 'mut'}">Data from ${hm(meta.updated_at)}, ${ago(meta.updated_at)} ago`
    + (stale ? '. The generator has stopped or is slow.' : '.') + '</p>';
  if (!sessions.length) {
    h += '<p class="mut">No benchmark session in the last 3 hours.</p>';
  } else {
    h += '<table><tr><th>Scenario</th><th>Started</th><th>State</th><th>Runs</th><th>Now</th><th>Last runs (review total)</th></tr>'
      + sessions.map((r) => `<tr><td>${esc(r.scenario)}<div class="note">${esc(r.session_id)}</div></td>`
        + `<td>${hm(r.started_at)}</td>`
        + `<td><span class="pill p-${r.state === 'running' ? 'doing' : 'done'}">${esc(r.state)}</span></td>`
        + `<td>${esc(r.runs_finished)} finished, ${esc(r.runs_ok)} ok</td>`
        + `<td>${r.inflight_run ? `${esc(r.inflight_run)} running for ${ago(r.inflight_started_at)}` : '-'}</td>`
        + `<td class="sm">${esc(r.last_runs) || '-'}</td></tr>`).join('')
      + '</table>';
  }
  if (meta.runner_log) {
    h += `<details class="more"><summary>Runner log, last lines (UTC)</summary><pre class="sm">${esc(meta.runner_log)}</pre></details>`;
  }
}
render(h);
