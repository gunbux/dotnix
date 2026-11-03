// Pure rules for the watch API. The bridge feeds in T3 thread projections and
// gets back the small shapes the watch reads, so these rules test without T3.
//
// Pending item, as the watch receives it:
//   { rid, tid, thread, q, opts?, qs? }
// `qs` is present when the watch can answer the whole request: 1 to 4
// questions, each with 1 to 4 options, single- or multi-select. Each entry is
//   { h: header, q: question, m: multi-select, o: [[label, description], ...] }
// `opts` is the format of the first watch build (one single-select question,
// labels only). It stays so that build keeps working. Without `qs` the watch
// shows "Answer on phone".
//
// Answer body: { rid, tid, a: [[option index, ...], ...] }, one list per
// question in order. The first build sends { rid, tid, i } instead.

export const LIMITS = {
  thread: 40,
  question: 240,
  legacyQuestion: 120,
  header: 16,
  option: 24,
  label: 60,
  description: 90,
  options: 4,
  questions: 4,
};

const clip = (text, max) => {
  const flat = String(text ?? "").replace(/\s+/g, " ").trim();
  return flat.length <= max ? flat : flat.slice(0, max - 1) + "…";
};

const hasWatchOptions = (question) =>
  question.options.length >= 1 && question.options.length <= LIMITS.options;

const isWatchAnswerable = (questions) =>
  questions.length >= 1 && questions.length <= LIMITS.questions && questions.every(hasWatchOptions);

const isLegacyAnswerable = (questions) =>
  questions.length === 1 && !questions[0].multiSelect && hasWatchOptions(questions[0]);

const questionItem = (projection, requestId) =>
  projection.turnItems.find(
    (item) => item.type === "user_input_request" && item.requestId === requestId,
  );

const watchQuestion = (question) => ({
  h: clip(question.header, LIMITS.header),
  q: clip(question.question, LIMITS.question),
  m: question.multiSelect === true,
  o: question.options.map((o) => [clip(o.label, LIMITS.label), clip(o.description, LIMITS.description)]),
});

// One pending request as the watch item. `questions` uses T3's question
// shape ({ id, header, question, options, multiSelect }), which both the
// thread projection and the MCP tool t3_pending_request return.
export function watchItem({ rid, tid, thread, questions }) {
  const item = {
    rid,
    tid,
    thread: clip(thread, LIMITS.thread),
    q: clip(questions[0]?.question ?? "Open T3 to see this question", LIMITS.legacyQuestion),
  };
  if (isLegacyAnswerable(questions)) {
    item.opts = questions[0].options.map((o) => clip(o.label, LIMITS.option));
  }
  if (isWatchAnswerable(questions)) item.qs = questions.map(watchQuestion);
  return item;
}

export function pendingItems(projection) {
  const { thread } = projection;
  return projection.runtimeRequests
    .filter((request) => request.kind === "user_input" && request.status === "pending")
    .map((request) =>
      watchItem({
        rid: request.id,
        tid: thread.id,
        thread: thread.title,
        questions: questionItem(projection, request.id)?.questions ?? [],
      }),
    );
}

// Questions on a linked machine reach the watch with tid "<environmentId>/<threadId>".
// Thread ids can hold ":" (agent-launched threads) but never "/".
const PEER_TID = /^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\/(.+)$/;

export const peerTid = (environmentId, threadId) => `${environmentId}/${threadId}`;

export function parsePeerTid(tid) {
  const match = PEER_TID.exec(tid);
  return match === null ? null : { environmentId: match[1], threadId: match[2] };
}

const optionValue = (option) => option.value ?? option.label;

// Checks one question's picked indices: exactly one for single-select, one or
// more distinct ones for multi-select, all in range.
function pickedOptions(question, picks) {
  if (!Array.isArray(picks) || picks.length === 0) return null;
  if (!question.multiSelect && picks.length !== 1) return null;
  if (new Set(picks).size !== picks.length) return null;
  const options = picks.map((i) => (Number.isInteger(i) ? question.options[i] : undefined));
  return options.includes(undefined) ? null : options;
}

// Turns watch picks into a T3 answers record for these questions. `picks`
// is the `a` list, or a bare index from the first watch build. Returns
// either { answer, question, label } or { status, error }.
export function answerFor(questions, picks) {
  const legacy = !Array.isArray(picks);
  if (legacy ? !isLegacyAnswerable(questions) : !isWatchAnswerable(questions)) {
    return { status: 422, error: "answer_on_phone" };
  }
  const lists = legacy ? [[picks]] : picks;
  if (lists.length !== questions.length) return { status: 422, error: "bad_index" };
  const answer = {};
  const labels = [];
  for (const [n, question] of questions.entries()) {
    const options = pickedOptions(question, lists[n]);
    if (options === null) return { status: 422, error: "bad_index" };
    // T3 takes a string for single-select and a list for multi-select.
    answer[question.id] = question.multiSelect ? options.map(optionValue) : optionValue(options[0]);
    labels.push(options.map((o) => o.label).join(", "));
  }
  return {
    answer,
    question: questions.map((q) => q.question).join(" | "),
    label: labels.join(" | "),
  };
}

// Decides what one watch answer means for one thread projection.
export function resolveAnswer(projection, requestId, picks) {
  const request = projection.runtimeRequests.find(
    (r) => r.id === requestId && r.kind === "user_input",
  );
  if (request === undefined) return { status: 404, error: "not_found" };
  if (request.status === "resolved") return { status: 409, error: "already_answered" };
  if (request.status !== "pending") return { status: 404, error: `not_pending:${request.status}` };
  return answerFor(questionItem(projection, requestId)?.questions ?? [], picks);
}
