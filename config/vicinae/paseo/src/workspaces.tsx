import {
  Action,
  ActionPanel,
  Alert,
  closeMainWindow,
  Color,
  confirmAlert,
  Icon,
  Keyboard,
  List,
  showToast,
  Toast,
} from "@vicinae/api";
import { useMemo } from "react";
import { showFailure, useSnapshot } from "./lib/hooks";
import {
  type Agent,
  archiveWorkspace,
  GLANCE_LABEL,
  isQuickChat,
  openAgent,
  preferences,
  relativeTime,
  setPinned,
  type Workspace,
} from "./lib/paseo";

type Entry = { workspace: Workspace; agents: Agent[]; lastActive: number };

const STATUS_COLORS: Record<string, Color> = {
  running: Color.Green,
  attention: Color.Orange,
  error: Color.Red,
};

async function open(agent: Agent | undefined) {
  if (!agent) {
    await showToast({ style: Toast.Style.Failure, title: "This workspace has no agents to open" });
    return;
  }
  try {
    await openAgent(agent.id);
    await closeMainWindow({ clearRootSearch: true });
  } catch (error) {
    await showFailure("Could not open Paseo", error);
  }
}

function AgentList({ entry }: { entry: Entry }) {
  return (
    <List navigationTitle={entry.workspace.title} searchBarPlaceholder="Search agents">
      {entry.agents.map((agent) => (
        <List.Item
          key={agent.id}
          title={agent.title ?? agent.id.slice(0, 7)}
          subtitle={agent.model ?? agent.provider}
          icon={{ source: Icon.CircleFilled, tintColor: STATUS_COLORS[agent.status] ?? Color.SecondaryText }}
          accessories={[{ text: relativeTime(agent.updatedAt) }]}
          actions={
            <ActionPanel>
              <Action title="Open in Paseo" icon={Icon.AppWindow} onAction={() => open(agent)} />
              <Action.CopyToClipboard title="Copy Agent ID" content={agent.id} />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}

export default function Workspaces() {
  const { data, isLoading, refresh } = useSnapshot();
  const { showQuickChats, chatLabel } = preferences();

  const projects = useMemo(() => {
    if (!data) return [];
    const entries: Entry[] = data.workspaces
      .filter((w) => !w.archivingAt && (showQuickChats || !(isQuickChat(w, chatLabel) || isQuickChat(w, GLANCE_LABEL))))
      .map((workspace) => {
        const agents = data.agents
          .filter((a) => a.workspaceId === workspace.id)
          .sort((a, b) => Date.parse(b.updatedAt) - Date.parse(a.updatedAt));
        const times = [workspace.activityAt, agents[0]?.updatedAt].map((t) => (t ? Date.parse(t) : 0));
        return { workspace, agents, lastActive: Math.max(...times) };
      })
      .sort((a, b) => b.lastActive - a.lastActive);
    // Projects keep the order of their most recently active workspace.
    const grouped = new Map<string, Entry[]>();
    for (const entry of entries) {
      const list = grouped.get(entry.workspace.project) ?? [];
      list.push(entry);
      grouped.set(entry.workspace.project, list);
    }
    return [...grouped];
  }, [data, showQuickChats, chatLabel]);

  const togglePin = async ({ workspace }: Entry) => {
    try {
      await setPinned(workspace.id, !workspace.pinnedAt);
      await showToast({ title: workspace.pinnedAt ? "Unpinned" : "Pinned; auto-archive will skip it" });
      await refresh();
    } catch (error) {
      await showFailure("Could not change pin", error);
    }
  };

  const archive = async ({ workspace }: Entry) => {
    const confirmed = await confirmAlert({
      title: `Archive "${workspace.title}"?`,
      message: "Its agents are archived too. Managed worktrees are removed from disk.",
      primaryAction: { title: "Archive", style: Alert.ActionStyle.Destructive },
    });
    if (!confirmed) return;
    try {
      await archiveWorkspace(workspace.id);
      await showToast({ title: "Workspace archived" });
      await refresh();
    } catch (error) {
      await showFailure("Could not archive workspace", error);
    }
  };

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Search Paseo workspaces and agents">
      {projects.map(([project, entries]) => (
        <List.Section key={project} title={project}>
          {entries.map((entry) => {
            const { workspace, agents } = entry;
            const running = agents.filter((a) => a.status === "running").length;
            const attention = agents.some((a) => a.requiresAttention);
            const accessories: List.Item.Accessory[] = [
              ...workspace.labels.map((label) => ({ tag: label })),
              ...(running ? [{ text: { value: `${running} running`, color: Color.Green } }] : []),
              ...(attention ? [{ icon: { source: Icon.Dot, tintColor: Color.Orange }, tooltip: "Needs attention" }] : []),
              ...(workspace.pinnedAt ? [{ icon: Icon.Pin, tooltip: "Pinned" }] : []),
              { text: relativeTime(entry.lastActive ? new Date(entry.lastActive).toISOString() : null) },
            ];
            return (
              <List.Item
                key={workspace.id}
                title={workspace.title}
                subtitle={workspace.kind === "worktree" && workspace.branch ? workspace.branch : ""}
                icon={{ source: Icon.CircleFilled, tintColor: STATUS_COLORS[workspace.status] ?? Color.SecondaryText }}
                keywords={[workspace.project, ...workspace.labels, ...agents.map((a) => a.title ?? "")]}
                accessories={accessories}
                actions={
                  <ActionPanel>
                    <Action title="Open in Paseo" icon={Icon.AppWindow} onAction={() => open(agents[0])} />
                    {agents.length > 1 && (
                      <Action.Push title="Show Agents" icon={Icon.AppWindowList} target={<AgentList entry={entry} />} />
                    )}
                    <Action
                      title={workspace.pinnedAt ? "Unpin Workspace" : "Pin Workspace"}
                      icon={workspace.pinnedAt ? Icon.PinDisabled : Icon.Pin}
                      shortcut={Keyboard.Shortcut.Common.Pin}
                      onAction={() => togglePin(entry)}
                    />
                    <Action
                      title="Archive Workspace"
                      icon={Icon.Tray}
                      style={Action.Style.Destructive}
                      shortcut={Keyboard.Shortcut.Common.Remove}
                      onAction={() => archive(entry)}
                    />
                    <Action.CopyToClipboard
                      title="Copy Path"
                      content={workspace.directory}
                      shortcut={Keyboard.Shortcut.Common.Copy}
                    />
                    <Action
                      title="Refresh"
                      icon={Icon.ArrowClockwise}
                      shortcut={Keyboard.Shortcut.Common.Refresh}
                      onAction={refresh}
                    />
                  </ActionPanel>
                }
              />
            );
          })}
        </List.Section>
      ))}
    </List>
  );
}
