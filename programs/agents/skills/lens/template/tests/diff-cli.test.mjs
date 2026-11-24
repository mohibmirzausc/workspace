// tests/diff-cli.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fixture, clone } from './fixture.mjs';
import { applyReview, EMPTY } from '../diff.mjs';
const require = createRequire(import.meta.url);
const { MARKER } = require('../components/graph-diff.js');
const page = '<html><body><main></main></body></html>';

test('injects one review layer before </body> and returns the summary', () => {
  const next = clone(fixture); next.nodes.find((n) => n.id === 'f-chat').title = 'Chat 2';
  const { html, text } = applyReview(page, fixture, next, 'HEAD');
  assert.equal(html.split(MARKER).length, 2);
  assert.ok(html.indexOf(MARKER) < html.indexOf('</body>'));
  assert.match(text, /~ node f-chat \(title\)/);
});

test('refuses a page that already carries a review layer', () => {
  const { html } = applyReview(page, fixture, fixture, 'HEAD');
  assert.throws(() => applyReview(html, fixture, fixture, 'HEAD'), /already carries a review layer/);
});

test('against an empty previous model everything is added', () => {
  const { text } = applyReview(page, EMPTY, fixture, 'HEAD');
  assert.match(text, /0 changed, 0 removed/);
});
