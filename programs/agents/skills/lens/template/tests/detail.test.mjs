// tests/detail.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fixture, clone } from './fixture.mjs';
const require = createRequire(import.meta.url);
const Detail = require('../components/detail.js');
const g = require('../components/graph.js').createGraph(fixture);
const opts = { images: {} };

test('a node page has its title, kind, connections grouped by relation and edge ids', () => {
  const html = Detail.detail(g, 'f-chat', opts);
  assert.match(html, /class="insp-pad"/);
  assert.match(html, /<h1>Chat<\/h1>/);
  assert.match(html, /Surface/);
  assert.match(html, /<h2>Serves<\/h2>/);
  assert.match(html, /data-edge="e-chat-serves"/);
  assert.match(html, /<h2>Decisions that shape it<\/h2>[\s\S]*data-node="d-home"/);
});

test('a claim id opens its owner with that claim focused', () => {
  const html = Detail.detail(g, 'a-builder-g1', opts);
  assert.match(html, /<h1>Builder<\/h1>/);
  assert.match(html, /class="claim focused" data-claim="a-builder-g1"/);
});

test('an edge page shows both ends and the edge claim', () => {
  const html = Detail.detail(g, 'e-alpha-fits', opts);
  assert.match(html, /data-node="p-alpha"[\s\S]*fits[\s\S]*data-node="a-builder"/);
  assert.match(html, /data-claim="e-alpha-fits-c"/);
});

test('kind-specific bodies: person conversations, source citations, decision fields, avatar channels', () => {
  assert.match(Detail.detail(g, 'p-alpha', opts), /data-node="s-call"/);
  assert.match(Detail.detail(g, 's-call', opts), /Claims that cite it/);
  assert.match(Detail.detail(g, 'd-home', opts), /Revisit when/);
  assert.match(Detail.detail(g, 'a-builder', opts), /data-node="c-peers"/);
});

test('every commentable id renders somewhere in its own detail', () => {
  for (const id of g.commentableIds()) {
    const html = Detail.detail(g, id, opts);
    assert.ok(html.includes(`"${id}"`), id);
  }
});

test('an unknown id renders a not-found note', () => {
  assert.match(Detail.detail(g, 'ghost', opts), /isn’t in the lens/);
});

test('a surface page links its ADRs separately from its code', async () => {
  const { clone } = await import('./fixture.mjs');
  const m = clone(fixture);
  m.nodes.find((n) => n.id === 'f-chat').adrs = ['docs/adr/010-chat-is-home.md'];
  const g2 = require('../components/graph.js').createGraph(m);
  const html = Detail.detail(g2, 'f-chat', { images: {}, repo: { url: 'https://github.com/o/r', sha: 'abc' } });
  assert.match(html, /<h2>Code<\/h2>[\s\S]*blob\/abc\/build\.mjs/);
  assert.match(html, /<h2>ADRs<\/h2>[\s\S]*blob\/abc\/docs\/adr\/010-chat-is-home\.md/);
});

test('a hypothesis page lists evidence as stance + (source, note), the same row as the home card', () => {
  const html = Detail.detail(g, 'h-recap', opts);
  assert.match(html, /<li class="supports"><span class="stance"[^>]*>＋<\/span><div><button class="ev" data-node="s-call">[^<]*<\/button><p class="ev-note">Alpha asked for one<\/p><\/div><\/li>/);
});

test('a product page shows every researched section with its source', () => {
  const html = Detail.detail(g, 'pr-acme', opts);
  for (const h of ['Pitch', 'Pricing', 'Revenue', 'Meta ads', 'TikTok ads', 'Notable', 'Compared with Fixture']) assert.match(html, new RegExp(`<h2>${h}</h2>`), h);
  assert.match(html, /Notes, faster/);
  assert.match(html, /href="https:\/\/acme\.example\/pricing"/);
  assert.match(html, /data-claim="pr-acme-vs"/);
  assert.match(html, /<h2>Is a<\/h2>[\s\S]*data-node="alt-notes"/);
});

test('a question shows what to ask and what a good answer looks like', () => {
  const html = Detail.detail(g, 'q-why', opts);
  assert.match(html, /<h2>Ask<\/h2>[\s\S]*When did you last open chat first\?/);
  assert.match(html, /<h2>A useful answer<\/h2>[\s\S]*A real example/);
});

test('a decision explains each piece of its evidence', () => {
  assert.match(Detail.detail(g, 'd-home', opts), /<h2>Why this evidence<\/h2>[\s\S]*data-node="s-owner"[\s\S]*Owner chose it\./);
});

test('a source shows its type, population and statistics', () => {
  const html = Detail.detail(g, 's-market', opts);
  assert.match(html, /Survey/);
  assert.match(html, /US adults 18–29/);
  assert.match(html, /<td>YouTube<\/td><td>95%<\/td>/);
});

test('each ad is a card: the creative, the exact text, a link to that ad, and our read of it', () => {
  const html = Detail.detail(g, 'pr-acme', opts);
  const card = html.slice(html.indexOf('<article class="ad-card"'));
  assert.match(card, /<video controls preload="none" poster="assets\/example\.png" src="assets\/ads\/pr-acme\/123\.mp4">/);
  assert.match(card, /<blockquote class="ad-text">Take notes faster\.\nTry it free\.<\/blockquote>/);
  assert.match(card, /<b>Acme Notes<\/b> · Learn more · started Oct 20, 2026/);
  assert.match(card, /href="https:\/\/www\.facebook\.com\/ads\/library\/\?id=123"[^>]*>View this ad in the library/);
  assert.match(card, /Our read/);
  assert.match(card, /<span class="theme">free trial<\/span>/);
  assert.match(card, /Appeals most to[\s\S]*data-node="a-builder"/);
});

test('an image-only ad shows the still, not a video player', () => {
  const m = clone(fixture);
  delete m.nodes.find((n) => n.id === 'pr-acme').metaAds.ads[0].video;
  const html = Detail.detail(require('../components/graph.js').createGraph(m), 'pr-acme', opts);
  assert.match(html, /<img class="ad-media" src="assets\/example\.png"/);
  assert.doesNotMatch(html, /<video/);
});

test('ads are ordered by impressions rank and show the rank, with a figure only when the library gave one', () => {
  const m = clone(fixture);
  const ads = m.nodes.find((n) => n.id === 'pr-acme').metaAds.ads;
  ads.push({ ...ads[0], id: '999', url: 'https://www.facebook.com/ads/library/?id=999', rank: 2, impressions: undefined });
  ads.reverse();
  const html = Detail.detail(require('../components/graph.js').createGraph(m), 'pr-acme', opts);
  assert.ok(html.indexOf('data-ad="123"') < html.indexOf('data-ad="999"'));
  assert.match(html, /<span class="ad-rank">#1 by impressions · 10K-15K<\/span>/);
  assert.match(html, /<span class="ad-rank">#2 by impressions<\/span>/);
});

test('a content idea page shows its format and its pillar', () => {
  const html = Detail.detail(g, 'ci-leash', opts);
  assert.match(html, /Content idea/);
  assert.match(html, /Short video/);
  assert.match(html, /<h2>Under<\/h2>[\s\S]*data-node="cp-play"/);
});

test('an insight page shows its findings, and what it bears on shows it back', () => {
  const html = Detail.detail(g, 'mi-shift', opts);
  assert.match(html, /Market insight/);
  assert.match(html, /data-claim="mi-shift-f1"/);
  assert.match(html, /<h2>Bears on<\/h2>[\s\S]*data-node="a-builder"/);
  assert.match(Detail.detail(g, 'a-builder', opts), /data-edge="e-shift-bears"/);
});
