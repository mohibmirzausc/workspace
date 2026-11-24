import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fixture, clone } from './fixture.mjs';
const require = createRequire(import.meta.url);
const Alternatives = require('../components/alternatives.js');
const Graph = require('../components/graph.js');
const g = Graph.createGraph(fixture);

test('one row per alternative with when the product wins and when it doesn’t', () => {
  const html = Alternatives.view(g);
  assert.match(html, /<h2>Instead of…<\/h2>/);
  assert.match(html, /data-node="alt-notes"/);
  assert.ok(html.indexOf('data-claim="alt-notes-w1"') < html.indexOf('data-claim="alt-notes-l1"'));
});

test('named products sit under their kind of alternative, as compact rows that open in detail', () => {
  const html = Alternatives.view(g);
  const row = html.slice(html.indexOf('data-node="alt-notes"'));
  assert.match(row, /<table class="products">/);
  assert.match(row, /<button[^>]*data-node="pr-acme"[^>]*>Acme Notes<\/button>/);
  assert.match(row, /<td>\$5\/mo<\/td>/, 'the table shows the short entry price');
  assert.doesNotMatch(row, /\$50\/yr/, 'full pricing lives in the detail page');
  assert.match(row, /<td>Not public<\/td>/, 'the table shows the revenue headline');
  assert.match(row, /class="ad-chip active"[^>]*>Meta ✓/);
  assert.match(row, /class="ad-chip none"[^>]*>TikTok —/);
});

test('what jumps out counts advertisers from the product data, so it stays current', () => {
  assert.deepEqual(Alternatives.adCounts(g), { products: 1, meta: 1, tiktok: 0 });
  const m = clone(fixture);
  m.nodes.find((n) => n.id === 'pr-acme').metaAds.status = 'none';
  const html = Alternatives.view(Graph.createGraph(m));
  assert.match(html, /0 of 1 products run Meta ads/);
  assert.match(html, /0 of 1 run TikTok ads/);
});
