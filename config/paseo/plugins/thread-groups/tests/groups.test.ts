import assert from 'node:assert/strict';
import { test } from 'node:test';
import { addGroup, renameGroup, deleteGroup, setMembers, assignThread, groupsSchema } from '../shared/groups.ts';

test('creates trimmed groups and rejects empty or duplicate names', () => {
  const doc = addGroup({ groups: [] }, 'g1', '  Login  ');
  assert.equal(doc.groups[0].name, 'Login');
  assert.throws(() => addGroup(doc, 'g2', 'login'), /already exists/);
  assert.throws(() => addGroup(doc, 'g2', '  '), /name/);
  assert.throws(() => addGroup(doc, 'g1', 'Other'), /ID/);
});
test('one thread belongs to multiple groups without losing other memberships', () => {
  let doc = addGroup(addGroup({ groups: [] }, 'a', 'Login'), 'b', 'Billing');
  doc = assignThread(doc, 'thread-1', ['a', 'b']);
  assert.deepEqual(doc.groups.map(g => g.agentIds), [['thread-1'], ['thread-1']]);
  doc = assignThread(doc, 'thread-2', ['a']);
  doc = assignThread(doc, 'thread-1', ['b']);
  assert.deepEqual(doc.groups.map(g => g.agentIds), [['thread-2'], ['thread-1']]);
});
test('deleting a group leaves other groups and thread IDs intact', () => {
  const doc = { groups: [
    { id: 'a', name: 'Login', agentIds: ['t1', 't2'] },
    { id: 'b', name: 'Billing', agentIds: ['t1'] },
  ] };
  const next = deleteGroup(doc, 'a');
  assert.deepEqual(next.groups, [{ id: 'b', name: 'Billing', agentIds: ['t1'] }]);
  assert.equal(doc.groups.length, 2);
});
test('rename preserves membership and rejects collisions', () => {
  const doc = { groups: [
    { id: 'a', name: 'Login', agentIds: ['t1'] },
    { id: 'b', name: 'Billing', agentIds: [] },
  ] };
  assert.deepEqual(renameGroup(doc, 'a', ' Auth ').groups[0], { id: 'a', name: 'Auth', agentIds: ['t1'] });
  assert.throws(() => renameGroup(doc, 'a', 'billing'), /already exists/);
});
test('batch membership preserves unavailable references and removes duplicates', () => {
  const doc = { groups: [{ id: 'a', name: 'Login', agentIds: ['missing', 't1'] }] };
  assert.deepEqual(setMembers(doc, 'a', ['missing', 't2', 't2']).groups[0].agentIds, ['missing', 't2']);
  assert.throws(() => setMembers(doc, 'absent', []), /not found/);
  assert.throws(() => assignThread(doc, 't1', ['absent']), /not found/);
});
test('persisted state defaults safely but rejects malformed or duplicate groups', () => {
  assert.deepEqual(groupsSchema.parse({}), { groups: [] });
  assert.equal(groupsSchema.safeParse({ groups: 'invalid' }).success, false);
  assert.equal(groupsSchema.safeParse({ groups: [
    { id: 'a', name: 'Login', agentIds: [] }, { id: 'a', name: 'Billing', agentIds: [] },
  ] }).success, false);
});
