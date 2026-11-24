// tests/graph.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fixture } from './fixture.mjs';
const require = createRequire(import.meta.url);
const Graph = require('../components/graph.js');
const g = Graph.createGraph(fixture);

test('claimsOf walks single and list claim fields with their paths', () => {
  const paths = g.claimsOf(g.node('a-builder')).map((c) => [c.path, c.claim.id]);
  assert.deepEqual(paths, [
    ['personaMap.background', 'a-builder-bg'], ['personaMap.context', 'a-builder-ctx'],
    ['personaMap.goals', 'a-builder-g1'], ['personaMap.frustrations', 'a-builder-f1'],
    ['personaMap.behaviors', 'a-builder-b1'], ['journeyMap.cells.setup:actions', 'a-builder-j1'],
  ]);
});

test('allClaims includes node, edge and purpose claims with their owner', () => {
  const owners = Object.fromEntries(g.allClaims().map((c) => [c.claim.id, c.owner]));
  assert.equal(owners['a-builder-g1'], 'a-builder');
  assert.equal(owners['e-alpha-fits-c'], 'e-alpha-fits');
  assert.equal(owners.purpose, null);
});

test('lookup resolves any id to node, claim or edge', () => {
  assert.equal(g.lookup('f-chat').type, 'node');
  assert.equal(g.lookup('f-chat-u1').type, 'claim');
  assert.equal(g.lookup('f-chat-u1').owner, 'f-chat');
  assert.equal(g.lookup('e-chat-serves').type, 'edge');
  assert.equal(g.lookup('nope'), null);
});

test('edges, neighbours and citations', () => {
  assert.deepEqual(g.edgesFrom('f-chat').map((e) => e.id), ['e-chat-serves', 'e-chat-implements']);
  assert.deepEqual(g.edgesTo('n-focus').map((e) => e.from), ['p-owner', 'a-builder', 'f-chat', 'alt-notes', 'f-idea']);
  assert.deepEqual(g.citationsOf('s-owner').map((c) => c.claim.id).sort(), ['a-builder-ctx', 'd-home-c', 'e-acme-is-c', 'e-builder-has-c', 'e-chat-implements-c', 'e-home-shapes-c', 'e-owner-reports-c', 'e-recap-about-c', 'e-trust-q-c', 'e-why-tests-c', 'f-chat-u1', 'p-owner-bg', 'purpose']);
});

test('commentableIds lists every node, claim and edge id once', () => {
  const ids = g.commentableIds();
  assert.equal(new Set(ids).size, ids.length);
  for (const id of ['a-builder', 'a-builder-g1', 'e-alpha-fits', 'e-alpha-fits-c', 'purpose']) assert.ok(ids.includes(id), id);
});

test('nodesOfKind keeps model order', () => {
  assert.deepEqual(g.nodesOfKind('person').map((n) => n.id), ['p-alpha', 'p-owner']);
});
