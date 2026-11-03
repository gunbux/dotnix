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
    qs: [
      {
        h: "Deploy",
        q: "Which environment should I deploy to?",
        m: false,
        o: [
          ["Staging", "Staging desc"],
          ["Production", "Production desc"],
        ],
      },
    ],
  });
});

test("the first watch build gets opts only for one single-select question", () => {
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

test("qs covers 1 to 4 questions of 1 to 4 options, single- or multi-select", () => {
  const five = question({ options: ["a", "b", "c", "d", "e"].map((l) => option(l)) });
  const items = pendingItems(
    projection([
      ["multi", "pending", "user_input", [question({ multiSelect: true })]],
      ["two", "pending", "user_input", [question(), question({ id: "q2", multiSelect: true })]],
      ["four", "pending", "user_input", [1, 2, 3, 4].map((n) => question({ id: `q${n}` }))],
      ["five-questions", "pending", "user_input", [1, 2, 3, 4, 5].map((n) => question({ id: `q${n}` }))],
      ["five-options", "pending", "user_input", [question(), five]],
      ["free", "pending", "user_input", [question({ options: [] })]],
      ["none", "pending", "user_input", []],
    ]),
  );
  assert.deepEqual(
    items.map((i) => [i.rid, i.qs?.length ?? 0]),
    [["multi", 1], ["two", 2], ["four", 4], ["five-questions", 0], ["five-options", 0], ["free", 0], ["none", 0]],
  );
  assert.equal(items[1].qs[1].m, true);
});

test("long text is clipped to the watch limits", () => {
  const long = "word ".repeat(100);
  const [item] = pendingItems(
    projection([["r1", "pending", "user_input", [question({ question: long, header: long, options: [option(long)] })]]]),
  );
  const [q] = item.qs;
  assert.equal(q.q.length, 240);
  assert.equal(q.h.length, 16);
  assert.equal(q.o[0][0].length, 60);
  assert.equal(item.opts[0].length, 24);
  assert.equal(q.o[0][1].length, 90);
  assert.equal(item.q.length, 120);
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

test("a lists answer: a string for single-select, a list for multi-select", () => {
  const p = projection([
    ["r1", "pending", "user_input", [question(), question({ id: "q2", multiSelect: true })]],
  ]);
  const resolved = resolveAnswer(p, "r1", [[1], [0, 1]]);
  assert.deepEqual(resolved.answer, { q1: "prod", q2: ["Staging", "prod"] });
  assert.equal(resolved.label, "Production | Staging, Production");
});

test("bad a lists get 422", () => {
  const p = projection([
    ["r1", "pending", "user_input", [question(), question({ id: "q2", multiSelect: true })]],
  ]);
  for (const bad of [
    [[0]],
    [[0], [1], [0]],
    [[0, 1], [0]],
    [[], [0]],
    [[0], []],
    [[0], [1, 1]],
    [[0], [2]],
    [[0], ["0"]],
    [0, [0]],
  ]) {
    assert.equal(resolveAnswer(p, "r1", bad).status, 422, JSON.stringify(bad));
  }
});

test("the first build's bare index works only on one single-select question", () => {
  const p = projection([
    ["one", "pending"],
    ["two", "pending", "user_input", [question(), question({ id: "q2" })]],
  ]);
  assert.deepEqual(resolveAnswer(p, "one", 1).answer, { q1: "prod" });
  assert.equal(resolveAnswer(p, "two", 0).status, 422);
  assert.deepEqual(resolveAnswer(p, "two", [[0], [1]]).answer, { q1: "Staging", q2: "prod" });
});
