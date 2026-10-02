import { defineSettings } from '@getpaseo/plugin';
import { groupsSchema } from './groups';

export const threadGroups = defineSettings({
  id: 'groups', scope: 'host', version: 1, schema: groupsSchema,
});
