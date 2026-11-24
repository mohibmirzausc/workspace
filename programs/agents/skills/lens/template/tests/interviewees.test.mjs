// tests/interviewees.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fixture } from './fixture.mjs';
const require = createRequire(import.meta.url);
const Interviewees = require('../components/interviewees.js');
const g = require('../components/graph.js').createGraph(fixture);

test('cards list every interviewee with avatars they fit', () => {
  const html = Interviewees.view(g);
  assert.match(html, /data-node="p-alpha"/);
  assert.match(html, /data-node="a-builder"/);
});

test('conversations lists a person’s sources oldest first', () => {
  const html = Interviewees.conversations(g, 'p-alpha');
  assert.match(html, /data-node="s-call"/);
  assert.match(html, /Oct 27, 2026/);
});
