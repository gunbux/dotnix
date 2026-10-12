import test from 'node:test';
import assert from 'node:assert/strict';
import { Telegram, TelegramError, splitText } from '../server/telegram.ts';

test('long messages preserve all text without splitting Unicode characters', () => {
  const text = 'a'.repeat(3999) + '😀' + 'b'.repeat(5000);
  const parts = splitText(text);
  assert.equal(parts.join(''), text);
  assert.ok(parts.every(p => p.length <= 4000 && !/^[\uDC00-\uDFFF]|[\uD800-\uDBFF]$/.test(p)));
});

test('Telegram 429 errors expose retry delay without leaking token or request text', async () => {
  const api = new Telegram('123:secret', new AbortController().signal, async () => new Response(JSON.stringify({ ok: false, error_code: 429, description: 'secret text', parameters: { retry_after: 7 } }), { status: 429 }));
  await assert.rejects(api.call('sendMessage', { text: 'private' }), error => {
    assert.ok(error instanceof TelegramError);
    assert.equal(error.retryAfter, 7);
    assert.doesNotMatch(String(error), /secret|private/);
    return true;
  });
});

test('network errors cannot expose the token-bearing URL', async () => {
  const api = new Telegram('123:secret', new AbortController().signal, async url => { throw new Error(String(url)); });
  await assert.rejects(api.call('getMe', {}), error => !String(error).includes('secret'));
});

test('polling sends the saved offset and requests only supported updates', async () => {
  let payload: unknown;
  const api = new Telegram('123:secret', new AbortController().signal, async (_url, init) => {
    payload = JSON.parse(String(init?.body));
    return new Response(JSON.stringify({ ok: true, result: [] }));
  });
  await api.updates(15);
  assert.deepEqual(payload, { offset: 15, timeout: 25, limit: 100, allowed_updates: ['message', 'callback_query'] });
});
