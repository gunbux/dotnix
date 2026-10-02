import type { PluginServerContext } from '@getpaseo/plugin/server';
import { threadGroups } from './shared/settings';

export default function contribute(server: PluginServerContext) {
  server.registerSettings(threadGroups);
  return () => {};
}
