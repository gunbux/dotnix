import {
  Action,
  ActionPanel,
  Alert,
  closeMainWindow,
  confirmAlert,
  Detail,
  Form,
  Icon,
  Keyboard,
  type LaunchProps,
  List,
  showToast,
  useNavigation,
} from "@vicinae/api";
import { useCallback, useEffect, useRef, useState } from "react";
import manifest from "../package.json";
import { showFailure, useSnapshot } from "./lib/hooks";
import {
  archiveWorkspace,
  ask,
  type AskEvent,
  history,
  isQuickChat,
  openAgent,
  preferences,
  relativeTime,
  setPinned,
  type Turn,
} from "./lib/paseo";

// The chat model choices are the ones offered in the extension preferences.
const MODELS = manifest.preferences.find((p) => p.name === "model")?.data ?? [];

function modelTitle(value: string) {
  if (value === "custom") return preferences().customModel || "Custom model";
  return MODELS.find((m) => m.value === value)?.title ?? value;
}

function FollowUp({ onSubmit }: { onSubmit: (prompt: string) => void }) {
  const { pop } = useNavigation();
  return (
    <Form
      navigationTitle="Follow up"
      actions={
        <ActionPanel>
          <Action.SubmitForm
            title="Send"
            icon={Icon.Reply}
            onSubmit={(values) => {
              const prompt = String(values["prompt"] ?? "").trim();
              if (!prompt) return;
              pop();
              onSubmit(prompt);
            }}
          />
        </ActionPanel>
      }
    >
      <Form.TextArea id="prompt" title="Follow up" placeholder="Ask a follow-up question" />
    </Form>
  );
}

type ChatRef = { agentId: string; workspaceId: string | null };

// A new chat (prompt) or an earlier one picked up again (resume).
type ChatProps = { model: string; prompt?: string; resume?: ChatRef & { pinned: boolean } };

function Chat({ prompt, model, resume }: ChatProps) {
  const [turns, setTurns] = useState<Turn[]>([]);
  const [busy, setBusy] = useState(false);
  const [chat, setChat] = useState<ChatRef | null>(resume ?? null);
  const [pinned, setPinnedState] = useState(resume?.pinned ?? false);
  const abort = useRef(new AbortController());
  useEffect(() => () => abort.current.abort(), []);

  // Sends text as a new turn, or with no text follows the agent's current turn.
  const send = useCallback(
    async (text: string, agentId?: string) => {
      setBusy(true);
      if (text) setTurns((all) => [...all, { prompt: text, answer: "" }]);
      const update = (answer: string) =>
        setTurns((all) => all.map((turn, i) => (i === all.length - 1 ? { ...turn, answer } : turn)));
      try {
        await ask({ prompt: text, agentId, model, signal: abort.current.signal }, (event: AskEvent) => {
          if (event.type === "started" && !agentId) setChat({ agentId: event.agentId, workspaceId: event.workspaceId });
          else if (event.type === "text" || event.type === "done") update(event.text);
          else if (event.type === "warning") void showToast({ title: event.message });
        });
      } catch (error) {
        if (!abort.current.signal.aborted) await showFailure("Paseo chat failed", error);
      } finally {
        setBusy(false);
      }
    },
    [model],
  );

  // Runs once per mount; the chat being shown never changes.
  useEffect(() => {
    if (!resume) return void send(prompt ?? "");
    setBusy(true);
    history(resume.agentId).then(
      (past) => {
        setTurns(past.turns);
        // Still answering (e.g. the window was closed mid-reply): keep streaming.
        if (past.status === "running" || past.status === "initializing") void send("", resume.agentId);
        else setBusy(false);
      },
      (error) => {
        setBusy(false);
        void showFailure("Could not load chat", error);
      },
    );
  }, []);

  const last = turns[turns.length - 1];
  const markdown = turns
    .map((turn, i) => {
      const pending = busy && i === turns.length - 1 && !turn.answer;
      return `**${turn.prompt}**\n\n${pending ? "_Thinking…_" : turn.answer || "_No reply._"}`;
    })
    .join("\n\n---\n\n");

  const togglePin = async () => {
    if (!chat?.workspaceId) return;
    try {
      await setPinned(chat.workspaceId, !pinned);
      setPinnedState(!pinned);
      await showToast({ title: pinned ? "Chat will be auto-archived" : "Chat pinned; auto-archive will skip it" });
    } catch (error) {
      await showFailure("Could not change pin", error);
    }
  };

  return (
    <Detail
      navigationTitle={`${modelTitle(model)}${busy ? " · thinking…" : ""}`}
      markdown={markdown}
      actions={
        <ActionPanel>
          {chat && !busy && (
            <Action.Push
              title="Follow Up"
              icon={Icon.Reply}
              target={<FollowUp onSubmit={(text) => void send(text, chat.agentId)} />}
            />
          )}
          {last?.answer && <Action.CopyToClipboard title="Copy Answer" content={last.answer} />}
          {chat && (
            <Action
              title="Open in Paseo"
              icon={Icon.AppWindow}
              shortcut={Keyboard.Shortcut.Common.Open}
              onAction={async () => {
                await openAgent(chat.agentId).catch((error) => showFailure("Could not open Paseo", error));
                await closeMainWindow({ clearRootSearch: true });
              }}
            />
          )}
          {chat?.workspaceId && (
            <Action
              title={pinned ? "Unpin Chat" : "Pin Chat"}
              icon={pinned ? Icon.PinDisabled : Icon.Pin}
              shortcut={Keyboard.Shortcut.Common.Pin}
              onAction={togglePin}
            />
          )}
        </ActionPanel>
      }
    />
  );
}

export default function AskPaseo(props: LaunchProps<{ arguments: { question?: string } }>) {
  const initial = props.arguments.question?.trim() ?? "";
  const prefs = preferences();
  const [model, setModel] = useState(prefs.model || "opencode/openrouter/openrouter/free");
  const [text, setText] = useState("");
  const { data, isLoading, refresh } = useSnapshot();
  const { push } = useNavigation();

  // Asked straight from the root search: skip the prompt list.
  useEffect(() => {
    if (initial) push(<Chat prompt={initial} model={model} />);
  }, []);

  const chats = (data?.workspaces ?? [])
    .filter((w) => !w.archivingAt && isQuickChat(w, prefs.chatLabel))
    .map((workspace) => ({ workspace, agent: data?.agents.find((a) => a.workspaceId === workspace.id) }))
    .filter((chat) => !text || chat.workspace.title.toLowerCase().includes(text.toLowerCase()));

  const archive = async (workspaceId: string, title: string) => {
    if (!(await confirmAlert({ title: `Archive "${title}"?`, primaryAction: { title: "Archive", style: Alert.ActionStyle.Destructive } }))) return;
    try {
      await archiveWorkspace(workspaceId);
      await refresh();
    } catch (error) {
      await showFailure("Could not archive chat", error);
    }
  };

  return (
    <List
      isLoading={isLoading}
      filtering={false}
      searchText={text}
      onSearchTextChange={setText}
      searchBarPlaceholder="Ask Paseo…"
      searchBarAccessory={
        <List.Dropdown tooltip="Model" value={model} onChange={setModel}>
          {MODELS.map((m) => (
            <List.Dropdown.Item key={m.value} title={modelTitle(m.value)} value={m.value} />
          ))}
        </List.Dropdown>
      }
    >
      {text.trim() && (
        <List.Item
          title={text.trim()}
          subtitle={`Ask ${modelTitle(model)}`}
          icon={Icon.SpeechBubble}
          actions={
            <ActionPanel>
              <Action.Push title="Ask" icon={Icon.SpeechBubble} target={<Chat prompt={text.trim()} model={model} />} />
            </ActionPanel>
          }
        />
      )}
      <List.Section title="Recent quick chats">
        {chats.map(({ workspace, agent }) => (
          <List.Item
            key={workspace.id}
            title={workspace.title}
            subtitle={agent?.model ?? ""}
            icon={workspace.pinnedAt ? Icon.Pin : Icon.SpeechBubbleActive}
            accessories={[{ text: relativeTime(workspace.activityAt) }]}
            actions={
              <ActionPanel>
                {text.trim() && (
                  <Action.Push title="Ask" icon={Icon.SpeechBubble} target={<Chat prompt={text.trim()} model={model} />} />
                )}
                {agent && (
                  <Action.Push
                    title="Continue"
                    icon={Icon.SpeechBubbleActive}
                    target={
                      <Chat
                        model={agent.model ?? model}
                        resume={{ agentId: agent.id, workspaceId: workspace.id, pinned: Boolean(workspace.pinnedAt) }}
                      />
                    }
                  />
                )}
                {agent && (
                  <Action
                    title="Continue in Paseo"
                    icon={Icon.AppWindow}
                    onAction={async () => {
                      await openAgent(agent.id).catch((error) => showFailure("Could not open Paseo", error));
                      await closeMainWindow({ clearRootSearch: true });
                    }}
                  />
                )}
                <Action
                  title={workspace.pinnedAt ? "Unpin Chat" : "Pin Chat"}
                  icon={workspace.pinnedAt ? Icon.PinDisabled : Icon.Pin}
                  shortcut={Keyboard.Shortcut.Common.Pin}
                  onAction={() => setPinned(workspace.id, !workspace.pinnedAt).then(refresh, (e) => showFailure("Could not change pin", e))}
                />
                <Action
                  title="Archive Chat"
                  icon={Icon.Tray}
                  style={Action.Style.Destructive}
                  shortcut={Keyboard.Shortcut.Common.Remove}
                  onAction={() => archive(workspace.id, workspace.title)}
                />
              </ActionPanel>
            }
          />
        ))}
      </List.Section>
    </List>
  );
}
