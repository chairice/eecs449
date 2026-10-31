// Run after the Jac client build. These tests exercise the emitted dispatcher;
// browser QA covers React Router ordering and Back/Forward undo/replay.
import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import * as atlasState from '../web/.jac/client/compiled/client/atlas_state.js';
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

// Run the actual emitted component with lightweight hook/JSX adapters. This
// exercises its event wiring without a second browser or a dependency on CSS.
function studioFixture() {
  const cells = []; const refs = []; const effects = []; const documentEvents = {};
  const historyMoves = [];
  let cellIndex = 0; let refIndex = 0; let historyHandler;
  const source = readFileSync(new URL('../web/.jac/client/compiled/components/AtlasStudio.js', import.meta.url), 'utf8')
    .replace(/^import .*;\n/gm, '').replace(/^export /gm, '');
  const component = runInNewContext(`${source}\nAtlasStudio;`, {
    ...atlasState,
    __jacJsx: (type, props, children) => ({ type, props, children }),
    useNavigate: () => () => {},
    useJacState(initial) {
      const index = cellIndex++;
      if (!cells[index]) cells[index] = { val: initial, set(value) { this.val = value; } };
      return cells[index];
    },
    useRef(initial) { const index = refIndex++; return refs[index] ??= { current: initial }; },
    useEffect: effect => effects.push(effect),
    load_atlas: () => ({ journeys: [], draft: atlasState.new_journey(), error: '' }),
    write_atlas: () => '',
    set_atlas_history_handler: handler => { historyHandler = handler; },
    __jacCallFunction: () => new Promise(() => {}), // No network in component tests.
    AtlasMap: () => {},
    window: { history: { state: { idx: 1 }, go: delta => historyMoves.push(delta) },
      addEventListener() {}, removeEventListener() {} },
    document: { addEventListener: (name, callback) => { documentEvents[name] = callback; }, removeEventListener() {} },
  });
  const render = () => { cellIndex = 0; refIndex = 0; effects.length = 0; return component(); };
  render(); effects.slice().forEach(effect => effect()); // Recover a dirty draft.
  render(); effects.at(-1)(); // Subscribe with the recovered draft's dirty state.
  return { render, historyMoves, documentEvents, history: event => historyHandler(event) };
}

function findElement(tree, predicate) {
  if (!tree || typeof tree !== 'object') return null;
  if (predicate(tree)) return tree;
  for (const child of (tree.children ?? []).flat(Infinity)) {
    const found = findElement(child, predicate);
    if (found) return found;
  }
  return null;
}

test('browser Back reveals the unsaved dialog when a dirty journey is presenting', () => {
  const fixture = studioFixture();
  findElement(fixture.render(), element => element.type === 'button' && element.children.includes('Present')).props.onClick();
  assert.match(fixture.render().props.className, /is-presenting/);
  fixture.history({ state: { idx: 0 }, stopImmediatePropagation() {} });
  assert.deepEqual(fixture.historyMoves, [1]);
  fixture.history({ state: { idx: 1 }, stopImmediatePropagation() {} });
  const tree = fixture.render();
  assert.doesNotMatch(tree.props.className, /is-presenting/);
  assert.ok(findElement(tree, element => element.props?.role === 'dialog' && element.props['aria-label'] === 'Unsaved journey'));
});

test('internal navigation also exits presentation before showing the dirty-draft guard', () => {
  const fixture = studioFixture();
  findElement(fixture.render(), element => element.type === 'button' && element.children.includes('Present')).props.onClick();
  const anchor = { getAttribute: () => '/plan' };
  fixture.documentEvents.click({ target: { closest: () => anchor }, preventDefault() {}, stopPropagation() {} });
  const tree = fixture.render();
  assert.doesNotMatch(tree.props.className, /is-presenting/);
  assert.ok(findElement(tree, element => element.props?.role === 'dialog'));
});
