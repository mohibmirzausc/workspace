// tests/ui.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fixture } from './fixture.mjs';
const require = createRequire(import.meta.url);
const Ui = require('../components/ui.js');
const g = require('../components/graph.js').createGraph(fixture);

test('esc escapes the five HTML characters', () => {
  assert.equal(Ui.esc(`<a href="x">'&'</a>`), '&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;');
});

test('badge names where a claim comes from in plain words, explained on hover', () => {
  assert.match(Ui.badge({ kind: 'observed' }), />Heard \/ seen</);
  assert.match(Ui.badge({ kind: 'observed' }), /title="Someone said or did this; open the evidence to check"/);
  assert.match(Ui.badge({ kind: 'hypothesis' }), />Untested</);
  const html = Ui.badge({ kind: 'view' });
  assert.match(html, /data-claim-kind="view"/);
  assert.match(html, /Owner’s view/);
  assert.doesNotMatch(html, /●/);
});

test('a bare claim drops its badge but keeps its comment anchor', () => {
  const html = Ui.claimBlock(g, g.lookup('a-builder-g1').value, { bare: true });
  assert.doesNotMatch(html, /claim-badge/);
  assert.match(html, /<span class="claim-head" data-cmt-key="claim:a-builder-g1"><\/span><p>a-builder-g1 text<\/p>/);
});

test('plural says people, not persons', () => {
  assert.equal(Ui.plural(1, 'person'), '1 person');
  assert.equal(Ui.plural(3, 'person'), '3 people');
  assert.equal(Ui.plural(2, 'source'), '2 sources');
});

test('claim evidence is folded away behind a source count', () => {
  const html = Ui.claimBlock(g, g.lookup('a-builder-g1').value);
  assert.match(html, /<details class="sources"><summary>Evidence \(1 source\)<\/summary>/);
  const two = { id: 'x', text: 't', kind: 'observed', evidence: [{ source: 's-call', at: '1' }, { source: 's-call', at: '2' }, { source: 's-owner', at: '3' }] };
  assert.match(Ui.claimBlock(g, two), /Evidence \(2 sources\)/);
  assert.doesNotMatch(Ui.claimBlock(g, { id: 'y', text: 't', kind: 'hypothesis', evidence: [] }), /<details/);
});

test('claimBlock carries data-claim, text, evidence and the next question', () => {
  const html = Ui.claimBlock(g, g.lookup('a-builder-g1').value);
  assert.match(html, /data-claim="a-builder-g1"/);
  assert.match(html, /a-builder-g1 text/);
  assert.match(html, /data-node="s-call"[^>]*>[^<]*Alpha call/);
  assert.match(html, /01:00/);
  assert.match(html, /What goal slipped last week\?/);
});

test('a claim carries its own comment anchor, keyed by id; the badge is a plain label', () => {
  const html = Ui.claimBlock(g, g.lookup('a-builder-g1').value);
  assert.match(html, /<span class="claim-head" data-cmt-key="claim:a-builder-g1"><span class="claim-badge"/);
  assert.doesNotMatch(html, /claim-open/, 'clicking a badge must not navigate');
});

test('chip links to a node with its kind icon', () => {
  assert.match(Ui.chip(g, 'f-chat'), /<button class="chip" data-node="f-chat">🧩 Chat<\/button>/);
  assert.equal(Ui.chip(g, 'ghost'), '');
});
