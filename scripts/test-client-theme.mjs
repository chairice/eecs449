// Run after jac build main.jac: the light/dark/system toggle logic as emitted for the browser.
import assert from 'node:assert/strict';
import test from 'node:test';
import { THEME_KEY, normal_preference, resolve_theme, load_preference,
  save_preference, system_prefers_dark, apply_theme, set_preference, theme_preference,
  watch_theme, initialize_theme } from '../web/.jac/client/compiled/client/theme_mode.js';

// A fake browser: localStorage, matchMedia with change listeners, <html>, storage events.
function browser({ stored = null, dark = false, blockStorage = false, noMatchMedia = false } = {}) {
  let raw = stored;
  const media = { matches: dark, listeners: [] };
  const windowListeners = {};
  const storage = {
    getItem(name) { assert.equal(name, THEME_KEY); return raw; },
    setItem(name, value) { assert.equal(name, THEME_KEY); raw = String(value); },
    removeItem(name) { assert.equal(name, THEME_KEY); raw = null; },
  };
  const win = {
    addEventListener(type, handler) { (windowListeners[type] ||= []).push(handler); },
  };
  Object.defineProperty(win, 'localStorage', { configurable: true,
    get() { if (blockStorage) throw new Error('SecurityError'); return storage; } });
  if (!noMatchMedia) {
    win.matchMedia = (query) => {
      assert.equal(query, '(prefers-color-scheme: dark)');
      return { get matches() { return media.matches; },
        addEventListener(type, handler) { assert.equal(type, 'change'); media.listeners.push(handler); } };
    };
  }
  const root = { dataset: {}, style: {} };
  globalThis.window = win;
  globalThis.document = { documentElement: root };
  return {
    root, raw: () => raw,
    setSystemDark(value) { media.matches = value; media.listeners.forEach(fn => fn({ matches: value })); },
    otherTab(value) { raw = value; (windowListeners.storage || []).forEach(fn => fn({ key: THEME_KEY })); },
  };
}

test('preferences normalise to light, dark or system', () => {
  assert.equal(normal_preference('light'), 'light');
  assert.equal(normal_preference('dark'), 'dark');
  for (const value of ['system', null, undefined, '', 'DARK', 'blue', 1, {}, []]) {
    assert.equal(normal_preference(value), 'system');
  }
});

test('system follows the OS; explicit choices override it', () => {
  assert.equal(resolve_theme('system', true), 'dark');
  assert.equal(resolve_theme('system', false), 'light');
  assert.equal(resolve_theme('light', true), 'light');
  assert.equal(resolve_theme('dark', false), 'dark');
  assert.equal(resolve_theme('garbage', true), 'dark');
});

test('choices persist; system clears the stored key', () => {
  const page = browser();
  assert.equal(load_preference(), 'system');
  assert.equal(save_preference('dark'), true);
  assert.equal(page.raw(), 'dark');
  assert.equal(load_preference(), 'dark');
  assert.equal(save_preference('system'), true);
  assert.equal(page.raw(), null);
  browser({ stored: 'tampered' });
  assert.equal(load_preference(), 'system');
});

test('blocked storage and missing matchMedia never throw', () => {
  browser({ blockStorage: true, noMatchMedia: true });
  assert.equal(load_preference(), 'system');
  assert.equal(save_preference('dark'), false);
  assert.equal(system_prefers_dark(), false);
  delete globalThis.document;
  assert.doesNotThrow(() => apply_theme('dark'));
});

test('apply_theme writes data-theme and color-scheme on <html>', () => {
  const page = browser();
  apply_theme('dark');
  assert.equal(page.root.dataset.theme, 'dark');
  assert.equal(page.root.style.colorScheme, 'dark');
  apply_theme('anything else');
  assert.equal(page.root.dataset.theme, 'light');
  assert.equal(page.root.style.colorScheme, 'light');
});

test('initialise, toggle, follow the OS and other tabs', () => {
  delete globalThis.window?.__detourTheme;
  const page = browser({ stored: null, dark: true });
  initialize_theme();
  assert.equal(theme_preference(), 'system');
  assert.equal(page.root.dataset.theme, 'dark');

  const seen = [];
  const stop = watch_theme((value) => seen.push(value));
  set_preference('light');
  assert.equal(page.raw(), 'light');
  assert.equal(page.root.dataset.theme, 'light');
  // An explicit choice ignores OS changes.
  page.setSystemDark(false); page.setSystemDark(true);
  assert.equal(page.root.dataset.theme, 'light');

  set_preference('system');
  assert.equal(page.raw(), null);
  assert.equal(page.root.dataset.theme, 'dark');
  page.setSystemDark(false);
  assert.equal(page.root.dataset.theme, 'light');

  page.otherTab('dark');
  assert.equal(theme_preference(), 'dark');
  assert.equal(page.root.dataset.theme, 'dark');
  assert.deepEqual(seen, ['light', 'system', 'dark']);

  stop();
  set_preference('light');
  assert.deepEqual(seen, ['light', 'system', 'dark']);

  // A second call (every app render) installs nothing new.
  initialize_theme();
  page.setSystemDark(true);
  assert.equal(page.root.dataset.theme, 'light');
});
