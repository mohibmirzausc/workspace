// The confidence meter on focus hypotheses is computed from evidence, never set by hand.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { assess, LEVELS } = require('../components/confidence.js');
const Graph = require('../components/graph.js');

const src = (id, people, tag = 'Interview') => ({ id, kind: 'source', title: id, body: 'b', tag, author: 'a', people });
const model = (evidence) => ({ owner: 'p-owner', nodes: [
  src('s-a', ['p-a']), src('s-b', ['p-b']), src('s-c', ['p-c']), src('s-a2', ['p-a']),
  src('s-own', ['p-owner'], 'Owner view'), src('s-mkt', undefined, 'Market research'),
  { id: 'h', kind: 'hypothesis', title: 'h', body: 'b', evidence },
], edges: [] });
const run = (evidence) => { const g = Graph.createGraph(model(evidence)); return assess(g, g.node('h')); };
const ev = (source, stance = 'supports') => ({ source, at: '1', stance });

test('no evidence is untested', () => assert.equal(run([]).level, 'untested'));

test('the level follows distinct supporting interviewees', () => {
  assert.equal(run([ev('s-a')]).level, 'weak');
  assert.equal(run([ev('s-a'), ev('s-a2')]).level, 'weak');
  assert.equal(run([ev('s-a'), ev('s-b')]).level, 'emerging');
  assert.equal(run([ev('s-a'), ev('s-b'), ev('s-c')]).level, 'strong');
});

test('the owner’s view and sources without people never raise the level', () => {
  const r = run([ev('s-own'), ev('s-mkt')]);
  assert.equal(r.level, 'untested');
  assert.deepEqual(r.sources, { for: 2, against: 0 });
});

test('contradicting evidence drops a step; as many against as for is contested', () => {
  assert.equal(run([ev('s-a'), ev('s-b'), ev('s-c'), ev('s-a2', 'contradicts')]).level, 'emerging');
  assert.equal(run([ev('s-a'), ev('s-b', 'contradicts')]).level, 'contested');
  assert.equal(run([ev('s-a', 'contradicts')]).level, 'contested');
});

test('counts report people and sources on each side', () => {
  assert.deepEqual(run([ev('s-a'), ev('s-a2'), ev('s-b', 'contradicts')]), { level: 'contested', people: { for: 1, against: 1 }, sources: { for: 2, against: 1 } });
});

test('levels are ordered for the meter', () => assert.deepEqual(LEVELS, ['untested', 'weak', 'emerging', 'strong']));
