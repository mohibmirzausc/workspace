import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fixture, clone, claim } from './fixture.mjs';
const require = createRequire(import.meta.url);
const Surfaces = require('../components/surfaces.js');
const Graph = require('../components/graph.js');
const g = Graph.createGraph(fixture);
const REPO = { url: 'https://github.com/o/r', sha: 'abc123' };

test('avatarsServed follows serves → problem ← has', () => {
  assert.deepEqual(Surfaces.avatarsServed(g, 'f-chat'), ['a-builder']);
});

test('the Surfaces tab shows only shipped surfaces; Ideas only unbuilt ones', () => {
  const shipped = Surfaces.view(g, { ideas: false, codeDates: {}, repo: REPO });
  const ideas = Surfaces.view(g, { ideas: true, codeDates: {}, repo: REPO });
  assert.match(shipped, /data-node="f-chat"/);
  assert.doesNotMatch(shipped, /data-node="f-idea"/);
  assert.match(ideas, /data-node="f-idea"/);
  assert.doesNotMatch(ideas, /data-node="f-chat"/);
  assert.match(ideas, /class="card surface idea"/);
  assert.match(ideas, /Idea · not built/);
});

test('a surface card has a carousel and four headed sections in order', () => {
  const html = Surfaces.view(g, { ideas: false, codeDates: {}, repo: REPO });
  assert.match(html, /<div class="carousel" data-carousel>/);
  assert.match(html, /<img src="assets\/example\.png" alt="New chat"/);
  assert.match(html, /Design · captured Oct 28, 2026/);
  const order = ['What it does', 'When it’s used', 'What we’ve heard', 'Code', 'Decisions'].map((h) => html.indexOf(`<h4>${h}</h4>`));
  assert.ok(order.every((i, n) => i > -1 && (n === 0 || i > order[n - 1])), order.join(','));
});

test('what we’ve heard is an ordered list, newest evidence first', () => {
  const m = clone(fixture);
  const chat = m.nodes.find((n) => n.id === 'f-chat');
  chat.heard = [claim('f-chat-old'), { ...claim('f-chat-new'), evidence: [{ source: 's-owner', at: '1' }] }];
  const html = Surfaces.view(Graph.createGraph(m), { ideas: false, codeDates: {}, repo: REPO });
  assert.match(html, /<ol class="heard">/);
  assert.ok(html.indexOf('f-chat-new') < html.indexOf('f-chat-old'));
  const heard = html.slice(html.indexOf('<ol class="heard">'), html.indexOf('</ol>'));
  assert.doesNotMatch(heard, /claim-badge/, 'every heard note is observed; no badge needed');
  assert.match(heard, /data-claim="f-chat-new"/);
  assert.match(heard, /Evidence \(1 source\)/);
});

test('a screenshot older than the surface’s last code change is flagged', () => {
  assert.equal(Surfaces.stale('2026-10-28', '2026-10-29'), true);
  assert.equal(Surfaces.stale('2026-10-28', '2026-10-28'), false);
  assert.equal(Surfaces.stale('2026-10-28', undefined), false);
  const html = Surfaces.view(g, { ideas: false, codeDates: { 'f-chat': '2026-11-02' }, repo: REPO });
  assert.match(html, /Code changed since this screenshot \(Nov 2, 2026\)/);
});

test('an idea without mockups says so instead of an empty carousel', () => {
  assert.match(Surfaces.view(g, { ideas: true, codeDates: {}, repo: REPO }), /No mockup yet/);
});

test('code links are GitHub permalinks at the built commit: folders as tree, files as blob', () => {
  assert.equal(Surfaces.githubLink(REPO, 'src/notes/'), 'https://github.com/o/r/tree/abc123/src/notes/');
  assert.equal(Surfaces.githubLink(REPO, 'package.json'), 'https://github.com/o/r/blob/abc123/package.json');
  const html = Surfaces.view(g, { ideas: false, codeDates: {}, repo: REPO });
  assert.match(html, /<a href="https:\/\/github\.com\/o\/r\/blob\/abc123\/build\.mjs" target="_blank" rel="noopener"><code>build\.mjs<\/code><\/a>/);
});

test('decisions are separate from code: ADRs link to the record, lens decisions open in place', () => {
  const m = clone(fixture);
  m.nodes.find((n) => n.id === 'f-chat').adrs = ['docs/adr/010-chat-is-home.md'];
  const html = Surfaces.view(Graph.createGraph(m), { ideas: false, codeDates: {}, repo: REPO });
  const decisions = html.slice(html.indexOf('<h4>Decisions</h4>'));
  assert.match(decisions, /href="https:\/\/github\.com\/o\/r\/blob\/abc123\/docs\/adr\/010-chat-is-home\.md"[^>]*>ADR 010 · chat is home</);
  assert.match(decisions, /data-node="d-home"/);
  const code = html.slice(html.indexOf('<h4>Code</h4>'), html.indexOf('<h4>Decisions</h4>'));
  assert.doesNotMatch(code, /adrs/);
});
