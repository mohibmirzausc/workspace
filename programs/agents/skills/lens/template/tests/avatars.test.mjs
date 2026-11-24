// tests/avatars.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fixture } from './fixture.mjs';
const require = createRequire(import.meta.url);
const Avatars = require('../components/avatars.js');
const g = require('../components/graph.js').createGraph(fixture);

test('cards show each avatar with its problems and interviewees', () => {
  const html = Avatars.view(g, { images: {} });
  assert.match(html, /data-node="a-builder"/);
  assert.match(html, /data-node="n-focus"/);
  assert.match(html, /data-node="p-alpha"/);
});

test('an avatar image comes from the build-supplied images map', () => {
  const html = Avatars.view(g, { images: { 'a-builder': 'data:image/png;base64,AAA' } });
  assert.match(html, /<img[^>]+src="data:image\/png;base64,AAA"/);
});

test('personaMap renders every section with badged claims in order', () => {
  const html = Avatars.personaMap(g, g.node('a-builder'), null);
  for (const t of ['Background', 'Context', 'Goals', 'Frustrations', 'Behaviors']) assert.match(html, new RegExp(`<h2>${t}</h2>`));
  assert.ok(html.indexOf('a-builder-bg') < html.indexOf('a-builder-b1'));
  assert.match(Avatars.personaMap(g, g.node('a-builder'), 'a-builder-g1'), /class="claim focused" data-claim="a-builder-g1"/);
});

test('the journey map is a stage × row grid; empty cells show a dash', () => {
  const html = Avatars.journeyMap(g, g.node('a-builder'), null);
  assert.match(html, /<section class="journey-map"><h2>🗺️ Journey<\/h2>/);
  assert.match(html, /Partly mapped from evidence/);
  const empty = { ...g.node('a-builder'), journeyMap: { ...g.node('a-builder').journeyMap, cells: {} } };
  assert.match(Avatars.journeyMap(g, empty, null), /Not mapped yet · stage labels are proposed\. We’ll use this to develop onboarding together\./);
  assert.match(html, /<caption>Journey for Builder · blank cells have not been researched or agreed<\/caption>/);
  assert.match(html, /<th scope="col">Experience<\/th><th scope="col">Discovery<\/th><th scope="col">Setup<\/th>/);
  assert.match(html, /<th scope="row">Actions<\/th><td class="unmapped"[^>]*>—<\/td><td[^>]*>[\s\S]*data-claim="a-builder-j1"/);
});

test('an avatar without a journey map shows none', () => {
  assert.equal(Avatars.journeyMap(g, { ...g.node('a-builder'), journeyMap: undefined }, null), '');
});

test('an empty journey cell shows its prompt, and every cell takes its own comment', () => {
  const n = { ...g.node('a-builder'), journeyMap: { ...g.node('a-builder').journeyMap, hints: { 'discovery:emotions': 'Describe how they feel here' } } };
  const html = Avatars.journeyMap(g, n, null);
  assert.match(html, /<td class="unmapped" data-cmt-key="journey:discovery:emotions">Describe how they feel here<\/td>/);
  assert.match(html, /<td class="unmapped" data-cmt-key="journey:discovery:actions">—<\/td>/);
});
