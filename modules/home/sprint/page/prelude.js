// Shared by every page panel. Business Text runs this before its template,
// with `context` holding the query results (panelData), Handlebars and
// markdown-it. A builder puts its HTML in context.data.html, and the
// panel's template is just {{{html}}}. Grafana sanitizes the result.
const md = context.markdown;
const esc = (s) => context.handlebars.escapeExpression(s == null ? '' : String(s));
const inl = (s) => md.renderInline(s == null ? '' : String(s));
const rv = (s) => context.grafana.replaceVariables(s);
const view = rv('$subgoal');

// The rows of one query, by refId, as objects.
const rows = (ref) => {
  const f = ((context.panelData && context.panelData.series) || []).find((s) => s.refId === ref);
  if (!f || !f.fields.length) return [];
  const out = [];
  for (let i = 0; i < f.fields[0].values.length; i++) {
    const r = {};
    f.fields.forEach((x) => { r[x.name] = x.values[i]; });
    out.push(r);
  }
  return out;
};

const pill = (s) => `<span class="pill p-${esc(String(s).split(' ')[0])}">${esc(s)}</span>`;
const bar = (p) => `<div class="bar"><span style="width:${Math.max(0, Math.min(100, Number(p) || 0))}%"></span></div>`;
const when = (t) => new Date(Number(t) * 1000).toLocaleString('en-GB',
  { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });
// This dashboard with another View ("-" is the whole sprint).
const viewLink = (key) => '/d/sprint/sprint?' + rv('${sprint:queryparam}&from=${__from}&to=${__to}')
  + '&var-subgoal=' + encodeURIComponent(key);

// Rendered Markdown with its table body rows and list items marked .fit,
// so ./fit.js can fold them when the panel is full.
const mdFit = (s) => md.render(s == null ? '' : String(s))
  .replace(/<tbody>[\s\S]*?<\/tbody>/g, (b) => b.replace(/<tr>/g, '<tr class="fit">'))
  .replace(/<li>/g, '<li class="fit">');

const ctxHtml = (list, openFirst) => list.map((r, n) =>
  `<details class="ctx"${openFirst && n === 0 ? ' open' : ''}><summary>${esc(r.title)}`
  + `<span class="mut sm"> · updated ${when(r.at)}</span></summary>${mdFit(r.body)}</details>`).join('');

// Blank lines would end Markdown's HTML block, so the output has none.
const render = (html) => {
  const theme = context.grafana.theme.isDark ? 'dark' : 'light';
  if (context.data) context.data.html = `<div class="sp ${theme} sp-p-${panelName}">${html}</div>`.replace(/\n\s*\n/g, '\n');
};
