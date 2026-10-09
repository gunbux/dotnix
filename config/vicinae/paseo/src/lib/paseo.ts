import { execFile, spawn } from "node:child_process";
import { homedir } from "node:os";
import { createInterface } from "node:readline";
import { promisify } from "node:util";
import { getPreferenceValues } from "@vicinae/api";

// Substituted with store paths by modules/home/vicinae.nix.
const BRIDGE = "@paseoBridge@";
const PASEO = "@paseo@";

const run = promisify(execFile);

export type Preferences = {
  model: string;
  customModel: string;
  thinking: string;
  readOnly: boolean;
  chatDirectory: string;
  chatLabel: string;
  showQuickChats: boolean;
};

export type Workspace = {
  id: string;
  title: string;
  project: string;
  directory: string;
  kind: string;
  status: string;
  labels: string[];
  pinnedAt: string | null;
  archivingAt: string | null;
  activityAt: string | null;
  branch: string | null;
};

export type Agent = {
  id: string;
  title: string | null;
  status: string;
  workspaceId: string | null;
  provider: string;
  model: string | null;
  labels: Record<string, string>;
  updatedAt: string;
  requiresAttention: boolean;
};

export type Snapshot = { serverId: string; workspaces: Workspace[]; agents: Agent[] };

export type Turn = { prompt: string; answer: string };
export type History = { status: string; turns: Turn[] };

export type AskEvent =
  | { type: "started"; agentId: string; workspaceId: string | null }
  | { type: "text"; text: string }
  | { type: "done"; text: string; status: string }
  | { type: "warning"; message: string };

type BridgeEvent = AskEvent | { type: "error"; message: string };

// Agents started from Vicinae carry this label, alongside the workspace label.
export const SOURCE_LABEL = { source: "vicinae" };

export const preferences = () => getPreferenceValues<Preferences>();

const expandHome = (path: string) => path.replace(/^~(?=$|\/)/, homedir());

async function bridge<T>(...args: string[]): Promise<T> {
  const { stdout } = await run(BRIDGE, args, { maxBuffer: 16 * 1024 * 1024 });
  const result = JSON.parse(stdout);
  if (result?.type === "error") throw new Error(result.message);
  return result;
}

export const snapshot = () => bridge<Snapshot>("snapshot");
export const archiveWorkspace = (id: string) => bridge("archive", id);
export const setPinned = (id: string, pinned: boolean) => bridge("pin", id, pinned ? "1" : "0");
export const history = (agentId: string) => bridge<History>("history", agentId);

/** Focuses Paseo Desktop on an agent, launching it if needed. */
export async function openAgent(agentId: string) {
  await run(PASEO, ["agent", "open", agentId]);
}

/** Splits "provider/model" (the model may itself contain slashes). */
export function resolveModel(choice: string, custom: string) {
  const value = (choice === "custom" ? custom : choice).trim();
  const slash = value.indexOf("/");
  return slash === -1 ? { provider: value, model: "" } : { provider: value.slice(0, slash), model: value.slice(slash + 1) };
}

// Codex has no read-only mode, so it keeps its default.
const PLAN_MODES: Record<string, string> = { claude: "plan", opencode: "plan" };

export type AskOptions = { prompt: string; agentId?: string | undefined; model: string; signal?: AbortSignal };

/**
 * Starts a quick chat (or follows up on one) and streams bridge events. With an
 * agentId and an empty prompt it only follows the agent's current turn.
 */
export function ask({ prompt, agentId, model, signal }: AskOptions, onEvent: (event: AskEvent) => void) {
  const prefs = preferences();
  const { provider, model: modelId } = resolveModel(model, prefs.customModel);
  const request = agentId
    ? { agentId, prompt }
    : {
        prompt,
        provider,
        model: modelId,
        thinking: prefs.thinking,
        modeId: prefs.readOnly ? PLAN_MODES[provider] : undefined,
        cwd: expandHome(prefs.chatDirectory || "~/.local/share/paseo/quick-chat"),
        workspaceLabel: prefs.chatLabel.trim() || undefined,
        labels: SOURCE_LABEL,
      };
  return new Promise<void>((resolve, reject) => {
    const child = spawn(BRIDGE, ["ask", JSON.stringify(request)], { signal, stdio: ["ignore", "pipe", "pipe"] });
    let stderr = "";
    let failure = "";
    child.stderr.on("data", (chunk) => (stderr += chunk));
    createInterface({ input: child.stdout }).on("line", (line) => {
      let event: BridgeEvent;
      try {
        event = JSON.parse(line);
      } catch {
        return; // Stray non-JSON output from the runtime.
      }
      if (event.type === "error") failure = event.message;
      else onEvent(event);
    });
    child.on("error", reject);
    child.on("close", (code) =>
      code === 0 ? resolve() : reject(new Error(failure || stderr.trim() || `Bridge exited with ${code}`)),
    );
  });
}

// glance's ask-about-screen chats (programs.glance.settings.paseoLabel in
// modules/home/glance.nix); the switcher hides them along with quick chats.
export const GLANCE_LABEL = "Glance";

export const isQuickChat = (workspace: Workspace, label: string) => workspace.labels.includes(label);

export function relativeTime(iso: string | null) {
  if (!iso) return "";
  const seconds = (Date.now() - Date.parse(iso)) / 1000;
  if (seconds < 60) return "now";
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h`;
  return `${Math.floor(seconds / 86400)}d`;
}
