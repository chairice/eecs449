// Pure boundary tests against the emitted JavaScript used by the browser.
import assert from 'node:assert/strict';
import test from 'node:test';
import { ComposerInput, validate_composer } from '../web/.jac/client/compiled/client/composer_model.js';
import { request_payload, restore_composer } from '../web/.jac/client/compiled/client/planning_request.js';

function payload() {
  const form = new ComposerInput({ origin_text: 'Ann Arbor', destination_text: 'Chicago',
    local_date: '2026-10-23', local_time: '16:00', budget: '50.01',
    priority: 'MOST_RELIABLE', allow_bus: false, request_text: 'Keep my request' });
  return request_payload(validate_composer(form).draft);
}

test('RPC whitelist excludes prose and restores all explicit constraints', () => {
  const request = payload();
  assert.equal(Object.keys(request).length, 9);
  assert.equal('request_text' in request, false);
  assert.equal(request.max_price_cents, 5001);
  const restored = restore_composer({ draft: request, requestText: 'Keep my request' });
  assert.equal(restored.request_text, 'Keep my request');
  assert.equal(restored.origin_text, 'Ann Arbor');
  assert.equal(restored.destination_text, 'Chicago');
  assert.equal(restored.local_date, '2026-10-23');
  assert.equal(restored.local_time, '16:00');
  assert.equal(restored.time_kind, 'DEPART_AFTER');
  assert.equal(restored.priority, 'MOST_RELIABLE');
  assert.equal(restored.budget, '50.01');
  assert.equal(restored.transfer_minutes, '30');
  assert.equal(restored.allow_train, true);
  assert.equal(restored.allow_bus, false);
});

test('malformed history produces a safe empty form', () => {
  for (const state of [undefined, null, 'bad', [], 1, true, {}, { draft: [] }, { draft: {} }]) {
    assert.equal(restore_composer(state).origin_text, '');
  }
  for (const [field, value] of [['min_transfer_minutes', true], ['max_price_cents', -1],
    ['max_price_cents', 1.5], ['max_price_cents', NaN], ['allowed_modes', ['FLIGHT']],
    ['allowed_modes', []], ['priority', 'BOGUS'], ['local_date', '2026-02-30']]) {
    assert.equal(restore_composer({ draft: { ...payload(), [field]: value } }).origin_text, '');
  }
});

test('free and absent budget remain distinct; invalid prose is ignored', () => {
  assert.equal(restore_composer({ draft: { ...payload(), max_price_cents: 0 } }).budget, '0.00');
  assert.equal(restore_composer({ draft: { ...payload(), max_price_cents: null } }).budget, '');
  assert.equal(restore_composer({ draft: payload(), requestText: ['bad'] }).request_text, '');
});
