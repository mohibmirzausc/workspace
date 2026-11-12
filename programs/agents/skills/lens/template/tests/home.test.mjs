import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fixture, clone } from './fixture.mjs';
const require = createRequire(import.meta.url);
const Home = require('../components/home.js');
const Graph = require('../components/graph.js');
const g = Graph.createGraph(fixture);

test('opens on the purpose, then the focus hypotheses, then the loop', () => {
  const html = Home.view(g);
  const at = (s) => html.indexOf(s);
  assert.ok(at('data-claim="purpose"') < at('data-node="h-recap"'));
  assert.ok(at('data-node="h-recap"') < at('data-node="l-capture"'));
});

test('a focus hypothesis shows its meter, counts, evidence and next questions', () => {
  const html = Home.view(g);
  assert.match(html, /class="meter" data-level="weak"/);
  assert.match(html, /1 person · 1 source · 0 against/);
  assert.match(html, /data-node="s-call"[^>]*>[^<]*Alpha call · 02:00/);
  assert.match(html, /Would you open a recap every morning\?/);
});

test('focus hypotheses render in focus order, at most three', () => {
  const m = clone(fixture);
  m.nodes.push({ ...clone(m.nodes.find((n) => n.id === 'h-recap')), id: 'h-two', title: 'Second', focus: 2 });
  m.nodes.find((n) => n.id === 'h-recap').focus = 3;
  const html = Home.view(Graph.createGraph(m));
  assert.ok(html.indexOf('data-node="h-two"') < html.indexOf('data-node="h-recap"'));
});

test('shows the three newest pieces of evidence and folds the rest', () => {
  const m = clone(fixture);
  const h = m.nodes.find((n) => n.id === 'h-recap');
  h.evidence = ['01', '02', '03', '04', '05'].map((at) => ({ source: 's-call', at, stance: 'supports' }));
  const html = Home.view(Graph.createGraph(m));
  assert.match(html, /\+2 more/);
});

test('other hypotheses are folded away, grouped, with no meter', () => {
  const html = Home.view(g);
  const other = html.slice(html.indexOf('<details class="disclosure">'));
  assert.match(other, /<details/);
  assert.match(other, /Trust &amp; failure/);
  assert.match(other, /data-node="h-trust"/);
  assert.doesNotMatch(other, /class="meter"/);
});
