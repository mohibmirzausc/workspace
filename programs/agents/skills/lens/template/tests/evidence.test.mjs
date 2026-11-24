// tests/evidence.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fixture } from './fixture.mjs';
const require = createRequire(import.meta.url);
const Evidence = require('../components/evidence.js');
const g = require('../components/graph.js').createGraph(fixture);
const state = { search: '', tag: 'all', sort: 'newest' };

test('lists sources newest first with date, people and tag', () => {
  const html = Evidence.view(g, state);
  assert.ok(html.indexOf('data-node="s-owner"') < html.indexOf('data-node="s-call"'));
  assert.match(html, /Oct 27, 2026/);
  assert.match(html, /Alpha/);
  assert.match(html, /data-tag="Interview"/);
});

test('each row says how many claims cite it', () => {
  assert.match(Evidence.view(g, state), /cited by 13 claims/);
});

test('tag counts follow the search, and a search by person finds their source', () => {
  const html = Evidence.view(g, { ...state, search: 'alpha' });
  assert.match(html, /data-node="s-call"/);
  assert.doesNotMatch(html, /data-node="s-owner"/);
  assert.match(html, /data-tag="Interview"[^>]*>Interview <small>1<\/small>/);
});

test('each source is one full-width row that expands to a summary before opening the full page', () => {
  const html = Evidence.view(g, state);
  assert.match(html, /<ol class="ev-items">/);
  const item = html.slice(html.indexOf('<li class="ev-item" data-node="s-call">'));
  assert.match(item, /^<li class="ev-item" data-node="s-call"><details><summary><span class="ev-date">Oct 27, 2026<\/span><span class="ev-title">Alpha call<\/span><span class="ev-people">Alpha<\/span><span class="ev-cited">cited by \d+ claims<\/span><span class="tag">Interview<\/span><\/summary>/);
  const body = item.slice(0, item.indexOf('</li>'));
  assert.match(body, /<div class="ev-body"><p>b<\/p>/);
  assert.match(body, /<button class="ev-open" data-node="s-call">Open full evidence →<\/button>/);
});
