// tests/schema.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const Schema = require('../components/schema.js');

test('every claim field belongs to a field its kind allows', () => {
  for (const [kind, paths] of Object.entries(Schema.CLAIM_FIELDS)) {
    const allowed = [...Schema.KINDS[kind].required, ...Schema.KINDS[kind].optional];
    for (const p of paths) assert.ok(allowed.includes(p.split('.')[0]), `${kind}.${p}`);
  }
});

test('relations only name known kinds', () => {
  for (const r of Schema.RELATIONS) {
    for (const k of [r.from, r.to]) assert.ok(k === '*' || Schema.KINDS[k], `${r.relation}: ${k}`);
  }
});

test('relationAllowed accepts listed pairs and wildcard targets, rejects others', () => {
  assert.equal(Schema.relationAllowed('person', 'fits', 'avatar'), true);
  assert.equal(Schema.relationAllowed('question', 'tests', 'surface'), true);
  assert.equal(Schema.relationAllowed('question', 'tests', 'source'), false);
  assert.equal(Schema.relationAllowed('avatar', 'fits', 'person'), false);
});

test('a product is a kind of alternative', () => {
  assert.equal(Schema.relationAllowed('product', 'is-a', 'alternative'), true);
  assert.equal(Schema.relationAllowed('product', 'is-a', 'surface'), false);
});
