import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fixture } from './fixture.mjs';
const require = createRequire(import.meta.url);
const Insights = require('../components/insights.js');
const g = require('../components/graph.js').createGraph(fixture);

test('one card per market insight with its findings and what it bears on', () => {
  const html = Insights.view(g);
  assert.match(html, /<h2>Market insights<\/h2>/);
  const card = html.slice(html.indexOf('data-node="mi-shift"'));
  assert.match(card, /Layoffs push people into solo work/);
  assert.match(card, /data-claim="mi-shift-f1"/);
  assert.match(card, /Bears on[\s\S]*data-node="a-builder"/);
});
