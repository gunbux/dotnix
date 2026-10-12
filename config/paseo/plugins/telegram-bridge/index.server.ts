import type { PluginHookContext, PluginServerContext } from '@getpaseo/plugin/server';
import { isAbsolute } from 'node:path';
import { bridgeSettings, type Config } from './shared/settings.ts';
import { bridgeStatus } from './shared/rpc.ts';
import { localConnection, requestLocal } from './server/local.ts';
import { agentPort } from './server/paseo.ts';
import { startRuntime, type Runtime } from './server/runtime.ts';

export default function contribute(server: PluginServerContext) {
  const settings = server.registerSettings(bridgeSettings);
  const home = process.env.PASEO_HOME ?? '';
  let paseo: PluginHookContext['paseo'] | null = null;
  let runtime: Runtime | null = null;
  let status = 'Disabled';
  let closed = false;
  let generation = 0;
  let controller: AbortController | null = null;
  let transition = Promise.resolve();
  let retry: ReturnType<typeof setTimeout> | undefined;
  const report = (next: string) => {
    if (next !== status) console.log(`[telegram-bridge] ${next}`);
    status = next;
  };
  const attach = (context: PluginHookContext | { paseo: PluginHookContext['paseo'] }) => { paseo = context.paseo; };
  const restart = (config: Config | null) => {
    const current = ++generation;
    controller?.abort();
    clearTimeout(retry);
    transition = transition.then(async () => {
      await runtime?.close();
      runtime = null;
      if (closed || current !== generation) return;
      if (!config) { report('Invalid settings. Fix them in Paseo.'); return; }
      if (!config.enabled) { report('Disabled'); return; }
      if (!isAbsolute(home)) { report('Paseo did not supply an absolute PASEO_HOME.'); return; }
      controller = new AbortController();
      const signal = controller.signal;
      try {
        if (!paseo) {
          report('Connecting to Paseo');
          await requestLocal(await localConnection(home), {
            type: 'plugin.rpc.invoke.request', pluginId: 'telegram-bridge', method: bridgeStatus.name, input: {},
          }, 'plugin.rpc.invoke.response', signal);
        }
        signal.throwIfAborted();
        if (!paseo) throw new Error('Paseo session is not available.');
        report('Connecting to Telegram');
        runtime = await startRuntime(config, agentPort(paseo, home, signal), home, signal, report);
      } catch {
        if (signal.aborted || closed) return;
        // Do not print SDK, filesystem, or fetch exceptions: they can contain secrets.
        report('Setup failed. Check the owner ID, private token file, bot webhook, and local Paseo TCP listener. Retrying in 30 seconds.');
        retry = setTimeout(() => restart(config), 30000);
      }
    }).catch(() => report('Bridge shutdown failed. Reload the plugin.'));
  };
  server.handle(bridgeStatus, (_input, context) => {
    attach(context);
    return { status, bot: null, selectedAgent: null, queued: 0, ...runtime?.snapshot() };
  });
  server.on('agent.turn_started', (_event, context) => attach(context));
  server.on('agent.turn_ended', (event, context) => {
    attach(context);
    runtime?.enqueue(bridge => bridge.finished(event.agent.id, event.agent.title ?? event.agent.id, event.timeline, event.outcome));
  });
  server.on('agent.permission_requested', (event, context) => {
    attach(context);
    runtime?.enqueue(bridge => bridge.permission(event.agent.id, event.request));
  });
  server.on('agent.permission_resolved', (event, context) => {
    attach(context);
    runtime?.enqueue(bridge => bridge.resolved(event.agent.id, event.requestId));
  });
  const unsubscribe = settings.subscribe(state => { restart(state.status === 'ready' ? state.values : null); });
  void settings.read().then(state => {
    if (generation === 0 && !closed) restart(state.status === 'ready' ? state.values : null);
  }).catch(() => report('Could not read settings.'));
  return async () => {
    closed = true;
    generation++;
    clearTimeout(retry);
    unsubscribe();
    controller?.abort();
    await transition;
    await runtime?.close();
  };
}
