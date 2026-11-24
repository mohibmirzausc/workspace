// tests/model.test.mjs
// This lens's own model: it must validate, and every commentable id must render in its detail panel.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildHtml, repoRoot } from '../build.mjs';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const Graph = require('../components/graph.js');
const Detail = require('../components/detail.js');
const dir = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const model = JSON.parse(fs.readFileSync(path.join(dir, 'model.json'), 'utf8'));
const lock = JSON.parse(fs.readFileSync(path.join(dir, 'ids.lock.json'), 'utf8'));

test('model.json builds with no errors against the committed id lock', () => {
  assert.deepEqual(buildHtml(model, { root: repoRoot(dir), lock }).errors, []);
});

test('every commentable id renders in its own detail panel', () => {
  const g = Graph.createGraph(model);
  for (const id of g.commentableIds()) assert.ok(Detail.detail(g, id, { images: {} }).includes(`"${id}"`), id);
});

test('the purpose is written', () => {
  assert.doesNotMatch(model.purpose.text, /TO WRITE/);
});
