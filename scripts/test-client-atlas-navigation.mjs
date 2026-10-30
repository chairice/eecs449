// Run after the Jac client build. These tests exercise the emitted dispatcher;
// browser QA covers React Router ordering and Back/Forward undo/replay.
import assert from 'node:assert/strict';
import test from 'node:test';
import { initialize_atlas_history, set_atlas_history_handler }
  from '../web/.jac/client/compiled/client/atlas_navigation.js';

function browserFixture(t) {
  const previous = Object.getOwnPropertyDescriptor(globalThis, 'window');
  const events = new EventTarget();
  const subscriptions = [];
  const browser = {
    addEventListener(type, listener, options) {
      subscriptions.push({ type, listener, options });
      events.addEventListener(type, listener, options);
    },
  };
  globalThis.window = browser;
  t.after(() => {
    if (previous) Object.defineProperty(globalThis, 'window', previous);
    else delete globalThis.window;
  });
  return { browser, subscriptions, dispatch: event => events.dispatchEvent(event) };
}

test('repeated app initialization installs exactly one capturing popstate listener', t => {
  const fixture = browserFixture(t);
  initialize_atlas_history();
  initialize_atlas_history();
  initialize_atlas_history();
  assert.equal(fixture.subscriptions.length, 1);
  assert.equal(fixture.subscriptions[0].type, 'popstate');
  assert.equal(fixture.subscriptions[0].options, true);
  assert.doesNotThrow(() => fixture.dispatch(new Event('popstate')));
});

test('registering before initialization works and dispatch always uses the newest handler', t => {
  const fixture = browserFixture(t);
  const calls = [];
  const first = new Event('popstate');
  const second = new Event('popstate');
  set_atlas_history_handler(event => calls.push(['first', event]));
  fixture.dispatch(first);
  set_atlas_history_handler(event => calls.push(['replacement', event]));
  initialize_atlas_history();
  fixture.dispatch(second);
  assert.deepEqual(calls, [['first', first], ['replacement', second]]);
  assert.equal(fixture.subscriptions.length, 1);
});

test('unregistering restores ordinary navigation while retaining the early dispatcher', t => {
  const fixture = browserFixture(t);
  let editorCalls = 0;
  let routerCalls = 0;
  set_atlas_history_handler(event => {
    editorCalls++;
    event.stopImmediatePropagation();
  });
  // Model a router listener registered after the app's early dispatcher.
  fixture.browser.addEventListener('popstate', () => { routerCalls++; });
  fixture.dispatch(new Event('popstate'));
  assert.equal(editorCalls, 1);
  assert.equal(routerCalls, 0);

  set_atlas_history_handler(null);
  fixture.dispatch(new Event('popstate'));
  assert.equal(editorCalls, 1);
  assert.equal(routerCalls, 1);

  set_atlas_history_handler(() => { editorCalls++; });
  fixture.dispatch(new Event('popstate'));
  assert.equal(editorCalls, 2);
  assert.equal(routerCalls, 2);
  assert.equal(fixture.subscriptions.length, 2); // Dispatcher plus the router.
});

test('a reloaded module reuses the window dispatcher and can replace its handler', async t => {
  const fixture = browserFixture(t);
  const calls = [];
  set_atlas_history_handler(() => calls.push('original'));
  const reloaded = await import('../web/.jac/client/compiled/client/atlas_navigation.js?navigation-test-reload');
  reloaded.initialize_atlas_history();
  fixture.dispatch(new Event('popstate'));
  reloaded.set_atlas_history_handler(() => calls.push('reloaded'));
  fixture.dispatch(new Event('popstate'));
  reloaded.set_atlas_history_handler(null);
  fixture.dispatch(new Event('popstate'));
  assert.deepEqual(calls, ['original', 'reloaded']);
  assert.equal(fixture.subscriptions.length, 1);
});
