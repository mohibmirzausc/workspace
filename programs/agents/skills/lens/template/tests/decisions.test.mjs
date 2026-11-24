import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fixture } from './fixture.mjs';
const require = createRequire(import.meta.url);
const Decisions = require('../components/decisions.js');
const g = require('../components/graph.js').createGraph(fixture);

test('lists each decision with now, before and why', () => {
  const html = Decisions.view(g);
  assert.match(html, /data-node="d-home"/);
  assert.match(html, /Start page/);
  assert.match(html, /Chat/);
});
