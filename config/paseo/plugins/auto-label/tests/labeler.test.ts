import assert from 'node:assert/strict';
import { test } from 'node:test';
import { chooseLabel, colorFor, normalizeLabel, vocabulary, COLORS, type Label, type Workspace } from '../shared/topics.ts';
import { createLabeler, type LabelerDeps } from '../server/labeler.ts';
import { settingsSchema } from '../shared/settings.ts';

test('labels normalize to short Title Case words', () => {
  assert.equal(normalizeLabel('  home-lab / nixOS! '), 'Home Lab NixOS');
  assert.equal(normalizeLabel('***'), '');
  assert.ok(normalizeLabel('a'.repeat(40)).length <= 24);
});
test('vocabulary prefers existing label casing and dedupes case-insensitively', () => {
  assert.deepEqual(vocabulary(['travel', 'nix'], [{ name: 'Travel', color: 'violet' }, { name: 'Vienna', color: 'sky' }]),
    ['Travel', 'Vienna', 'Nix', 'Misc']);
});
test('answers match existing labels; new labels only when allowed', () => {
  assert.equal(chooseLabel('travel', ['Travel'], false), 'Travel');
  assert.equal(chooseLabel('gardening', ['Travel'], false), 'Misc');
  assert.equal(chooseLabel('home lab', ['Travel'], true), 'Home Lab');
  assert.equal(chooseLabel('!!', ['Travel'], true), 'Misc');
});
test('colours reuse the catalog and are stable for new names', () => {
  assert.equal(colorFor('travel', [{ name: 'Travel', color: 'teal' }]), 'teal');
  assert.equal(colorFor('Nix', []), colorFor('nix', []));
  assert.ok(COLORS.includes(colorFor('Gardening', [])));
});

function harness(workspaces: Workspace[], answer = 'travel', overrides: Partial<LabelerDeps> = {}) {
  const assigned: [string, string][] = [];
  const prompts: string[] = [];
  const catalog: Label[] = [{ name: 'Travel', color: 'violet' }];
  const deps: LabelerDeps = {
    settings: async () => settingsSchema.parse({}),
    workspaces: async () => workspaces,
    catalog: async () => catalog,
    firstMessage: async () => 'plan my trip',
    classify: async prompt => { prompts.push(prompt); return answer; },
    assign: async (id, label) => {
      assigned.push([id, label.name]);
      workspaces.find(w => w.id === id)!.labels.push(label.name);
    },
    log: () => {},
    ...overrides,
  };
  return { labeler: createLabeler(deps), assigned, prompts };
}
const workspace = (id: string, labels: string[] = [], title: string | null = 'Trip'): Workspace =>
  ({ id, title, cwd: '/tmp', labels });

test('labels an unlabelled workspace with the existing label casing and leaves labelled ones', async () => {
  const { labeler, assigned, prompts } = harness([workspace('a'), workspace('b', ['Vienna'])]);
  assert.equal(await labeler.label('a'), 'Travel');
  assert.equal(await labeler.label('b'), null);
  assert.deepEqual(assigned, [['a', 'Travel']]);
  assert.match(prompts[0], /Travel/);
});
test('empty workspaces and disabled settings are skipped', async () => {
  const empty = harness([workspace('a', [], null)], 'travel', { firstMessage: async () => null });
  assert.equal(await empty.labeler.label('a'), null);
  const disabled = harness([workspace('a')], 'travel', { settings: async () => settingsSchema.parse({ enabled: false }) });
  assert.equal(await disabled.labeler.label('a'), null);
  assert.equal(await disabled.labeler.backfill(), 0);
  assert.equal(empty.assigned.length + disabled.assigned.length, 0);
});
test('a label applied by hand while classifying wins', async () => {
  const workspaces = [workspace('a')];
  const { labeler, assigned } = harness(workspaces, 'travel', {
    classify: async () => { workspaces[0].labels.push('Mine'); return 'travel'; },
  });
  assert.equal(await labeler.label('a'), null);
  assert.deepEqual(assigned, []);
});
test('backfill queues unlabelled workspaces once', async () => {
  const { labeler, assigned } = harness([workspace('a'), workspace('b'), workspace('done', ['Nix'])]);
  assert.equal(await labeler.backfill(), 2);
  assert.equal(await labeler.label('a'), null);
  // A workspace queued after the backfill resolves once the backfill has drained.
  await labeler.label('missing');
  assert.deepEqual(assigned, [['a', 'Travel'], ['b', 'Travel']]);
});
test('a failed classification does not block the queue', async () => {
  let calls = 0;
  const { labeler, assigned } = harness([workspace('a'), workspace('b')], 'travel', {
    classify: async () => { if (calls++ === 0) throw new Error('offline'); return 'travel'; },
  });
  await assert.rejects(labeler.label('a'), /offline/);
  assert.equal(await labeler.label('b'), 'Travel');
  assert.equal(await labeler.label('a'), 'Travel');
  assert.deepEqual(assigned, [['b', 'Travel'], ['a', 'Travel']]);
});
