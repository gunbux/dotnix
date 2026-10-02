import { z } from 'zod';

const groupSchema = z.object({
  id: z.string().min(1),
  name: z.string().trim().min(1).max(80),
  agentIds: z.array(z.string().min(1)),
});
export const groupsSchema = z.object({ groups: z.array(groupSchema).default([]) }).superRefine((doc, ctx) => {
  const ids = new Set<string>();
  const names = new Set<string>();
  for (const group of doc.groups) {
    if (ids.has(group.id) || names.has(group.name.toLowerCase())) {
      ctx.addIssue({ code: 'custom', message: 'Group IDs and names must be unique.' });
    }
    ids.add(group.id);
    names.add(group.name.toLowerCase());
  }
});
export type Groups = z.infer<typeof groupsSchema>;
export type Group = Groups['groups'][number];

function validName(doc: Groups, name: string, except?: string): string {
  const trimmed = name.trim();
  if (!trimmed || trimmed.length > 80) throw new Error('Use a group name between 1 and 80 characters.');
  if (doc.groups.some(g => g.id !== except && g.name.toLowerCase() === trimmed.toLowerCase())) {
    throw new Error('A group with that name already exists.');
  }
  return trimmed;
}
function requireGroup(doc: Groups, id: string): void {
  if (!doc.groups.some(g => g.id === id)) throw new Error('Group not found. Reload and try again.');
}
export function addGroup(doc: Groups, id: string, name: string): Groups {
  if (!id || doc.groups.some(g => g.id === id)) throw new Error('Group ID already exists or is empty.');
  return { groups: [...doc.groups, { id, name: validName(doc, name), agentIds: [] }] };
}
export function renameGroup(doc: Groups, id: string, name: string): Groups {
  requireGroup(doc, id);
  const nextName = validName(doc, name, id);
  return { groups: doc.groups.map(g => g.id === id ? { ...g, name: nextName } : g) };
}
export function deleteGroup(doc: Groups, id: string): Groups {
  requireGroup(doc, id);
  return { groups: doc.groups.filter(g => g.id !== id) };
}
export function setMembers(doc: Groups, id: string, agentIds: string[]): Groups {
  requireGroup(doc, id);
  return { groups: doc.groups.map(g => g.id === id ? { ...g, agentIds: [...new Set(agentIds)] } : g) };
}
export function assignThread(doc: Groups, agentId: string, groupIds: string[]): Groups {
  for (const id of groupIds) requireGroup(doc, id);
  return { groups: doc.groups.map(g => ({ ...g, agentIds: groupIds.includes(g.id)
    ? [...new Set([...g.agentIds, agentId])]
    : g.agentIds.filter(id => id !== agentId) })) };
}
