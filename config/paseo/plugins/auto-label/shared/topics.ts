export const COLORS = ['violet', 'sky', 'emerald', 'orange', 'pink', 'indigo', 'teal', 'red', 'amber', 'blue'] as const;
export type Color = typeof COLORS[number];
export type Label = { name: string; color: Color };
export type Workspace = { id: string; title: string | null; cwd: string; labels: string[] };
export const FALLBACK_LABEL = 'Misc';
const MAX_LENGTH = 24;

/** Title Case words of letters and digits, or '' when nothing usable remains. */
export function normalizeLabel(value: string): string {
  return value.replace(/[^A-Za-z0-9]+/g, ' ').trim().slice(0, MAX_LENGTH).trim()
    .split(' ').filter(Boolean).map(word => word[0].toUpperCase() + word.slice(1)).join(' ');
}

const key = (name: string) => name.toLowerCase();

/** Existing label names keep their casing; configured names fill in the rest. */
export function vocabulary(configured: string[], catalog: Label[]): string[] {
  const names = new Map<string, string>();
  for (const name of [...catalog.map(l => l.name), ...configured.map(normalizeLabel), FALLBACK_LABEL]) {
    if (name && !names.has(key(name))) names.set(key(name), name);
  }
  return [...names.values()];
}

export function chooseLabel(answer: string, topics: string[], allowNew: boolean): string {
  const existing = topics.find(t => key(t) === key(answer.trim()) || key(t) === key(normalizeLabel(answer)));
  if (existing) return existing;
  const name = normalizeLabel(answer);
  return allowNew && name ? name : FALLBACK_LABEL;
}

/** Stable colour per name, so a label keeps its colour if it is ever recreated. */
export function colorFor(name: string, catalog: Label[]): Color {
  const existing = catalog.find(l => key(l.name) === key(name));
  if (existing) return existing.color;
  let hash = 0;
  for (const char of key(name)) hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
  return COLORS[hash % COLORS.length];
}

export function buildPrompt(workspace: Workspace, firstMessage: string | null, topics: string[], allowNew: boolean): string {
  return [
    `Existing labels: ${topics.join(', ')}`,
    allowNew
      ? 'Reuse an existing label whenever one reasonably fits. Only invent a new one for a clearly distinct subject; make it a broad 1-2 word noun, not a task description.'
      : 'Answer with one of the existing labels exactly.',
    `Fall back to "${FALLBACK_LABEL}" when nothing fits.`,
    '',
    `Working directory: ${workspace.cwd}`,
    `Workspace title: ${workspace.title ?? '(none)'}`,
    `First message:\n${(firstMessage ?? '(none)').slice(0, 2000)}`,
  ].join('\n');
}

export const SYSTEM_PROMPT = 'You assign a single topic label to a coding-assistant workspace so the user can group related workspaces in a sidebar. Respond only with the structured label.';
