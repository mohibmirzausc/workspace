import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fixture, clone } from './fixture.mjs';
const require = createRequire(import.meta.url);
const Marketing = require('../components/marketing.js');
const Graph = require('../components/graph.js');
const g = Graph.createGraph(fixture);

test('one card per content pillar, with why it should work and the avatars it speaks to', () => {
  const html = Marketing.view(g);
  assert.match(html, /<h2>Content pillars<\/h2>/);
  const card = html.slice(html.indexOf('data-node="cp-play"'));
  assert.match(card, /data-claim="cp-play-c"/);
  assert.match(card, /class="chip" data-node="a-builder"/);
});

test('ideas sit under their pillar with their format, the surfaces they show and similar competitors', () => {
  const html = Marketing.view(g);
  const card = html.slice(html.indexOf('data-node="cp-play"'));
  const idea = card.slice(card.indexOf('data-node="ci-leash"'));
  assert.match(idea, /Leashed to my desk/);
  assert.match(idea, /Short video/);
  assert.match(idea, /data-claim="ci-leash-c"/);
  assert.match(idea, /Shows[\s\S]*data-node="f-chat"/);
  assert.match(idea, /Like[\s\S]*data-node="pr-acme"/);
});

test('a pillar with no ideas yet says so', () => {
  const m = clone(fixture);
  m.edges = m.edges.filter((e) => e.relation !== 'under');
  assert.match(Marketing.view(Graph.createGraph(m)), /No ideas yet/);
});
