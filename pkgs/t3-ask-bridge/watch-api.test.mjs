import assert from "node:assert/strict";
import { test } from "node:test";
import { pendingItems, resolveAnswer } from "./watch-api.mjs";

const option = (label, value) => ({ label, description: `${label} desc`, ...(value ? { value } : {}) });
const question = (extra = {}) => ({
  id: "q1",
  header: "Deploy",
  question: "Which environment should I deploy to?",
  options: [option("Staging"), option("Production", "prod")],
  ...extra,
});

function projection(requests) {
  return {
    thread: { id: "thread-1", title: "Ship the release notes and deploy the new build today" },
    runtimeRequests: requests.map(([id, status, kind = "user_input"]) => ({ id, status, kind })),
    turnItems: requests.map(([id, , , questions = [question()]]) => ({
      type: "user_input_request",
      requestId: id,
      questions,
    })),
  };
}

test("a single-select question with up to 4 options reaches the watch with its labels", () => {
  const [item] = pendingItems(projection([["r1", "pending"]]));
  assert.deepEqual(item, {
    rid: "r1",
    tid: "thread-1",
    thread: "Ship the release notes and deploy the n…",
    q: "Which environment should I deploy to?",
    opts: ["Staging", "Production"],
  });
});

test("questions the watch cannot answer come without options", () => {
  const five = question({ options: ["a", "b", "c", "d", "e"].map((l) => option(l)) });
  const items = pendingItems(
    projection([
      ["multi", "pending", "user_input", [question({ multiSelect: true })]],
      ["two", "pending", "user_input", [question(), question({ id: "q2" })]],
      ["five", "pending", "user_input", [five]],
      ["free", "pending", "user_input", [question({ options: [] })]],
    ]),
  );
  assert.deepEqual(
    items.map((i) => [i.rid, "opts" in i]),
    [["multi", false], ["two", false], ["five", false], ["free", false]],
  );
});

test("only pending user-input requests are listed; approvals and answered ones are not", () => {
  const items = pendingItems(
    projection([
      ["done", "resolved"],
      ["approval", "pending", "command"],
      ["open", "pending"],
    ]),
  );
  assert.deepEqual(items.map((i) => i.rid), ["open"]);
});

test("an answer sends the option value, or the label when there is no value", () => {
  const p = projection([["r1", "pending"]]);
  assert.deepEqual(resolveAnswer(p, "r1", 0).answer, { q1: "Staging" });
  assert.deepEqual(resolveAnswer(p, "r1", 1).answer, { q1: "prod" });
});

test("answers that cannot apply map to the watch's HTTP statuses", () => {
  const p = projection([
    ["answered", "resolved"],
    ["gone", "expired"],
    ["open", "pending"],
    ["multi", "pending", "user_input", [question({ multiSelect: true })]],
  ]);
  assert.equal(resolveAnswer(p, "missing", 0).status, 404);
  assert.equal(resolveAnswer(p, "gone", 0).status, 404);
  assert.equal(resolveAnswer(p, "answered", 0).status, 409);
  assert.equal(resolveAnswer(p, "open", 2).status, 422);
  assert.equal(resolveAnswer(p, "open", -1).status, 422);
  assert.equal(resolveAnswer(p, "open", "0").status, 422);
  assert.equal(resolveAnswer(p, "multi", 0).status, 422);
});
