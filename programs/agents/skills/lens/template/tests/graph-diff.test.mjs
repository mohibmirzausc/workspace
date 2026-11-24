// tests/graph-diff.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fixture, clone, claim } from './fixture.mjs';
const require = createRequire(import.meta.url);
const Diff = require('../components/graph-diff.js');

test('identical graphs have no changes', () => {
  assert.deepEqual(Diff.diffGraphs(fixture, clone(fixture)), { added: [], changed: [], removed: [] });
});

test('reports added, changed and removed nodes, edges and claims by id', () => {
  const next = clone(fixture);
  next.nodes.find((n) => n.id === 'a-builder').personaMap.goals[0].text = 'Sharper goal';
  next.nodes.find((n) => n.id === 'f-chat').title = 'Chat with history';
  next.nodes.find((n) => n.id === 'a-builder').personaMap.goals.push(claim('a-builder-g2'));
  next.edges = next.edges.filter((e) => e.id !== 'e-builder-peers');
  const d = Diff.diffGraphs(fixture, next);
  assert.deepEqual(d.added, [{ id: 'a-builder-g2', type: 'claim', title: 'a-builder-g2 text' }]);
  assert.deepEqual(d.changed, [
    { id: 'f-chat', type: 'node', title: 'Chat with history', fields: ['title'] },
    { id: 'a-builder-g1', type: 'claim', title: 'Sharper goal', fields: ['text'] },
  ]);
  assert.deepEqual(d.removed, [{ id: 'e-builder-peers', type: 'edge', title: 'a-builder may-reach-through c-peers' }, { id: 'e-builder-peers-c', type: 'claim', title: 'e-builder-peers-c text' }]);
});

test('adding a claim to a list does not mark the owner changed', () => {
  const next = clone(fixture);
  next.nodes.find((n) => n.id === 'a-builder').personaMap.goals.push(claim('a-builder-g2'));
  assert.ok(!Diff.diffGraphs(fixture, next).changed.some((c) => c.id === 'a-builder'));
});

test('summary prints one line per change', () => {
  const next = clone(fixture);
  next.nodes.find((n) => n.id === 'f-chat').title = 'Chat with history';
  assert.equal(Diff.summary(Diff.diffGraphs(fixture, next), 'HEAD'), 'Changes since HEAD: 0 added, 1 changed, 0 removed\n  ~ node f-chat (title)\n');
});

test('reviewLayer is marked, deterministic, and carries the ids', () => {
  const d = { added: [{ id: 'x', type: 'claim' }], changed: [{ id: 'y', type: 'node', fields: ['title'] }], removed: [{ id: 'z', type: 'edge', title: 'z title' }] };
  const a = Diff.reviewLayer(d, 'HEAD');
  assert.equal(a, Diff.reviewLayer(d, 'HEAD'));
  assert.ok(a.startsWith(Diff.MARKER));
  assert.match(a, /"added":\["x"\]/);
  assert.match(a, /"changed":\["y"\]/);
  assert.match(a, /z title/);
});

test('the banner lists each change on its own row; added and changed ones open the item', () => {
  const d = { added: [{ id: 'x', type: 'claim', title: 'New <claim>' }], changed: [{ id: 'y', type: 'node', title: 'Chat', fields: ['title'] }], removed: [{ id: 'z', type: 'edge', title: 'z title' }] };
  const html = Diff.reviewLayer(d, 'HEAD');
  assert.match(html, /<li class="added"><button data-node="x"><span class="kind">\+ claim<\/span> · New &lt;claim&gt;<\/button><\/li>/);
  assert.match(html, /<li class="changed"><button data-node="y"><span class="kind">~ node<\/span> · Chat<\/button><\/li>/);
  assert.match(html, /<li class="removed"><span class="kind">− edge<\/span> · z title<\/li>/);
  assert.match(html, /green added, yellow changed, red removed/);
});
