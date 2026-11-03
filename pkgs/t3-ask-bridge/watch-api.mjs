// Pure rules for the watch API. The bridge feeds in T3 thread projections and
// gets back the small shapes the watch reads, so these rules test without T3.
//
// Pending item, as the watch receives it:
//   { rid, tid, thread, q, opts? }
// `opts` is present only when the watch can answer: exactly one question,
// single-select, 1 to 4 options. Without `opts` the watch shows
// "Answer on phone".

export const LIMITS = { thread: 40, question: 120, option: 24, options: 4 };

const clip = (text, max) => {
  const flat = String(text).replace(/\s+/g, " ").trim();
  return flat.length <= max ? flat : flat.slice(0, max - 1) + "…";
};

const isWatchAnswerable = (questions) =>
  questions.length === 1 &&
  !questions[0].multiSelect &&
  questions[0].options.length >= 1 &&
  questions[0].options.length <= LIMITS.options;

const questionItem = (projection, requestId) =>
  projection.turnItems.find(
    (item) => item.type === "user_input_request" && item.requestId === requestId,
  );

export function pendingItems(projection) {
  const { thread } = projection;
  return projection.runtimeRequests
    .filter((request) => request.kind === "user_input" && request.status === "pending")
    .map((request) => {
      const questions = questionItem(projection, request.id)?.questions ?? [];
      const base = {
        rid: request.id,
        tid: thread.id,
        thread: clip(thread.title, LIMITS.thread),
        q: clip(questions[0]?.question ?? "Open T3 to see this question", LIMITS.question),
      };
      return isWatchAnswerable(questions)
        ? { ...base, opts: questions[0].options.map((o) => clip(o.label, LIMITS.option)) }
        : base;
    });
}

// Decides what one watch answer means for one thread projection. Returns
// either { answer } with the T3 answers record, or { status, error } with the
// HTTP status the watch gets.
export function resolveAnswer(projection, requestId, index) {
  const request = projection.runtimeRequests.find(
    (r) => r.id === requestId && r.kind === "user_input",
  );
  if (request === undefined) return { status: 404, error: "not_found" };
  if (request.status === "resolved") return { status: 409, error: "already_answered" };
  if (request.status !== "pending") return { status: 404, error: `not_pending:${request.status}` };
  const questions = questionItem(projection, requestId)?.questions ?? [];
  if (!isWatchAnswerable(questions)) return { status: 422, error: "answer_on_phone" };
  const [question] = questions;
  const option = question.options[index];
  if (!Number.isInteger(index) || option === undefined) return { status: 422, error: "bad_index" };
  return {
    answer: { [question.id]: option.value ?? option.label },
    question: question.question,
    label: option.label,
  };
}
