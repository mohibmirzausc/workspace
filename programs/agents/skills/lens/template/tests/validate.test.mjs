// tests/validate.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fixture, clone, claim } from './fixture.mjs';
const require = createRequire(import.meta.url);
const { validate, checkIdContinuity } = require('../components/validate.js');
const files = new Set(['build.mjs', 'assets/example.png', 'src/notes/', 'docs/adr/024-offline-sync.md']);
const env = { fileExists: (p) => files.has(p) };
const errorsAfter = (mutate) => { const m = clone(fixture); mutate(m); return validate(m, env); };
const node = (m, id) => m.nodes.find((n) => n.id === id);
const expectError = (mutate, pattern) => {
  const errors = errorsAfter(mutate);
  assert.ok(errors.some((e) => pattern.test(e)), `expected ${pattern} in:\n${errors.join('\n')}`);
};

test('the fixture is valid', () => assert.deepEqual(validate(fixture, env), []));

test('rule 1: ids are unique across nodes, edges and claims, and well formed', () => {
  expectError((m) => { node(m, 'n-focus').claim.id = 'f-chat'; }, /^f-chat: duplicate id/);
  expectError((m) => { node(m, 'q-why').id = 'Q_Why'; }, /^Q_Why: id must match/);
});

test('rule 2: every reference resolves', () => {
  expectError((m) => { m.edges[0].to = 'a-ghost'; }, /^e-alpha-fits: unknown node a-ghost/);
  expectError((m) => { node(m, 'n-focus').claim.evidence[0].source = 's-ghost'; }, /^n-focus-c: unknown source s-ghost/);
  expectError((m) => { node(m, 's-call').people = ['p-ghost']; }, /^s-call: people must name interviewees/);
  expectError((m) => { node(m, 'q-why').ask = 's-call'; }, /^q-why: ask must name a person or avatar/);
});

test('rule 3: kinds have exactly their fields', () => {
  expectError((m) => { node(m, 'q-why').kind = 'module'; }, /^q-why: unknown kind module/);
  expectError((m) => { delete node(m, 'f-chat').shipped; }, /^f-chat: missing shipped/);
  expectError((m) => { node(m, 'f-chat').status = 'implemented'; }, /^f-chat: unexpected field status/);
  expectError((m) => { node(m, 'f-chat').title = ' '; }, /^f-chat: missing title/);
  expectError((m) => { node(m, 'n-focus').claim.kind = 'reported'; }, /^n-focus-c: kind must be one of/);
  expectError((m) => { node(m, 'n-focus').claim.text = ''; }, /^n-focus-c: missing text/);
  expectError((m) => { node(m, 'f-chat').shipped = 'yes'; }, /^f-chat: shipped must be true or false/);
  expectError((m) => { node(m, 'c-peers').phase = 'launch'; }, /^c-peers: phase must be one of/);
});

test('rule 4: an observed claim cites evidence with a locator', () => {
  expectError((m) => { node(m, 'n-focus').claim.evidence = []; }, /^n-focus-c: observed claim needs evidence/);
  expectError((m) => { delete node(m, 'n-focus').claim.evidence[0].at; }, /^n-focus-c: evidence from s-call needs "at"/);
});

test('rule 5: a view claim cites a source by the owner', () => {
  expectError((m) => { m.purpose.evidence = [{ source: 's-call', at: '01:00' }]; }, /^purpose: owner’s view needs a source whose people include p-owner/);
});

test('claims carry no confidence; only focus hypotheses get a computed one', () => {
  expectError((m) => { node(m, 'n-focus').claim.confidence = 'low'; }, /^n-focus-c: unexpected claim field confidence/);
});

test('hypotheses: stance, locator, focus slots and a home', () => {
  expectError((m) => { node(m, 'h-recap').evidence[0].stance = 'maybe'; }, /^h-recap: evidence stance must be supports or contradicts/);
  expectError((m) => { delete node(m, 'h-recap').evidence[0].at; }, /^h-recap: evidence from s-call needs "at"/);
  expectError((m) => { node(m, 'h-recap').evidence[0].source = 's-ghost'; }, /^h-recap: unknown source s-ghost/);
  expectError((m) => { node(m, 'h-recap').focus = 4; }, /^h-recap: focus must be 1, 2 or 3/);
  expectError((m) => { node(m, 'h-trust').focus = 1; }, /^h-trust: focus 1 is already taken by h-recap/);
  expectError((m) => { node(m, 'h-recap').next = 'one question'; }, /^h-recap: next must be a list of questions/);
});

test('surfaces: shipped ones need a screenshot, and every screenshot must be real and dated', () => {
  expectError((m) => { node(m, 'f-chat').screenshots = []; }, /^f-chat: a shipped surface needs at least one screenshot/);
  expectError((m) => { node(m, 'f-chat').screenshots[0].file = 'assets/ghost.png'; }, /^f-chat: screenshot assets\/ghost.png does not exist/);
  expectError((m) => { node(m, 'f-chat').screenshots[0].file = '../x.png'; }, /^f-chat: screenshot \.\.\/x.png must be under assets\//);
  expectError((m) => { node(m, 'f-chat').screenshots[0].capturedAt = 'today'; }, /^f-chat: screenshot capturedAt must be YYYY-MM-DD/);
  expectError((m) => { node(m, 'f-chat').screenshots[0].origin = 'figma'; }, /^f-chat: screenshot origin must be app or design/);
  assert.ok(!errorsAfter((m) => { node(m, 'f-idea').screenshots = []; }).some((e) => e.startsWith('f-idea')));
});

test('rule 7: relations must fit their kind pair', () => {
  expectError((m) => { m.edges[0].relation = 'serves'; }, /^e-alpha-fits: person —serves→ avatar is not allowed/);
  expectError((m) => { delete m.edges[0].claim; }, /^e-alpha-fits: missing claim/);
});

test('rule 8: surface code and adrs paths exist in the repo', () => {
  expectError((m) => { node(m, 'f-chat').code = ['src/ghost/']; }, /^f-chat: code path src\/ghost\/ does not exist/);
  expectError((m) => { node(m, 'f-chat').adrs = ['../secrets.md']; }, /^f-chat: adrs path \.\.\/secrets\.md does not exist/);
});

test('rule 9: no orphans', () => {
  expectError((m) => { m.edges = m.edges.filter((e) => e.from !== 'c-peers' && e.to !== 'c-peers'); }, /^c-peers: not connected/);
  expectError((m) => { m.nodes.push({ id: 's-unread', kind: 'source', title: 'u', body: 'b', tag: 'Reference', author: 'x' }); }, /^s-unread: no claim cites this source/);
});

test('rule 10: loop order runs 1..n', () => {
  expectError((m) => { node(m, 'l-capture').order = 2; }, /^loop: order must run 1\.\.1/);
});

test('rule 11: sources keep one tag, a valid date and snapshots in sources/', () => {
  expectError((m) => { node(m, 's-call').tag = 'Call'; }, /^s-call: tag must be one of/);
  expectError((m) => { node(m, 's-call').date = '27 Oct'; }, /^s-call: date must be YYYY/);
  expectError((m) => { node(m, 's-call').snapshot = 'call.txt'; }, /^s-call: snapshot must be under sources\//);
});

test('products: sourced facts, closed ad statuses, and a research source', () => {
  expectError((m) => { node(m, 'pr-acme').metaAds.status = 'maybe'; }, /^pr-acme: metaAds.status must be one of active, none, blocked, not-covered/);
  expectError((m) => { node(m, 'pr-acme').tiktokAds.status = 'unknown'; }, /^pr-acme: tiktokAds.status must be one of/);
  expectError((m) => { delete node(m, 'pr-acme').revenue.headline; }, /^pr-acme: revenue needs a short headline/);
  expectError((m) => { delete node(m, 'pr-acme').pricing.entry; }, /^pr-acme: pricing needs a short entry price/);
  expectError((m) => { node(m, 'pr-acme').pricing.source = 'acme.example'; }, /^pr-acme: pricing.source must be an http\(s\) URL/);
  expectError((m) => { node(m, 'pr-acme').notable[0].source = ''; }, /^pr-acme: notable.source must be an http\(s\) URL/);
  expectError((m) => { node(m, 'pr-acme').revenue.text = 'about $2M'; }, /^pr-acme: revenue needs a source unless it is "Not public"/);
  expectError((m) => { node(m, 'pr-acme').research = 's-ghost'; }, /^pr-acme: research must name a source/);
});

test('journey maps: cells name a real stage and row, and hold claims', () => {
  expectError((m) => { node(m, 'a-builder').journeyMap.cells['launch:actions'] = []; }, /^a-builder: journey cell launch:actions names an unknown stage or row/);
  expectError((m) => { node(m, 'a-builder').journeyMap.stages.push({ id: 'setup', title: 'Again' }); }, /^a-builder: journey stage setup is duplicated/);
  expectError((m) => { node(m, 'a-builder').journeyMap.hints = { 'launch:actions': 'x' }; }, /^a-builder: journey hint launch:actions names an unknown stage or row/);
  expectError((m) => { node(m, 'a-builder').journeyMap.cells['setup:actions'] = 'did things'; }, /^a-builder: journey cell setup:actions must be a list of claims/);
});

test('ads: a permalink, verbatim text, a real still, closed themes and a real avatar', () => {
  const ad = (m) => node(m, 'pr-acme').metaAds.ads[0];
  expectError((m) => { ad(m).url = 'https://www.facebook.com/ads/library/'; }, /^pr-acme: ad 123 needs its own library permalink/);
  expectError((m) => { ad(m).text = ' '; }, /^pr-acme: ad 123 needs its exact text/);
  expectError((m) => { ad(m).image = 'assets/ghost.png'; }, /^pr-acme: ad 123 image assets\/ghost.png does not exist/);
  expectError((m) => { ad(m).video = 'elsewhere/x.mp4'; }, /^pr-acme: ad 123 video must be an .mp4 under assets\/ads\//);
  expectError((m) => { ad(m).analysis.themes = ['vibes']; }, /^pr-acme: ad 123 themes must come from/);
  expectError((m) => { ad(m).analysis.avatar = 'p-alpha'; }, /^pr-acme: ad 123 must name the avatar it appeals to/);
  expectError((m) => { ad(m).analysis.hook = ''; }, /^pr-acme: ad 123 analysis needs a hook, framing and why/);
  expectError((m) => { const a = node(m, 'pr-acme').metaAds.ads; a.push({ ...a[0], id: '125', url: 'https://www.facebook.com/ads/library/?id=125', rank: undefined }); }, /^pr-acme: metaAds ranks every ad by impressions or none/);
  expectError((m) => { ad(m).rank = 0; }, /^pr-acme: ad 123 rank by impressions must be a positive whole number/);
  expectError((m) => { const a = node(m, 'pr-acme').metaAds.ads; a.push({ ...a[0], id: '124', url: 'https://www.facebook.com/ads/library/?id=124' }); }, /^pr-acme: ad 124 shares rank 1 with another ad/);
});

test('optional detail fields are checked', () => {
  expectError((m) => { node(m, 'd-home').evidenceNotes[0].sourceId = 's-ghost'; }, /^d-home: evidence note names unknown source s-ghost/);
  expectError((m) => { node(m, 's-market').statistics[0].percent = 140; }, /^s-market: statistics need a platform and a percent from 0 to 100/);
});

test('id continuity: a vanished id needs a renamed entry', () => {
  const lock = ['a-builder', 'a-builder-g1', 'x-old'];
  assert.deepEqual(checkIdContinuity(lock, fixture), ['x-old: id disappeared; add it to "renamed" (new id, or null if removed on purpose)']);
  assert.deepEqual(checkIdContinuity(lock, { ...fixture, renamed: { 'x-old': null } }), []);
  assert.deepEqual(checkIdContinuity(lock, { ...fixture, renamed: { 'x-old': 'a-builder' } }), []);
  assert.deepEqual(checkIdContinuity(lock, { ...fixture, renamed: { 'x-old': 'a-ghost' } }), ['x-old: renamed to a-ghost, which does not exist']);
});

test('a content idea sits under a pillar, so it shows on the Marketing tab', () => {
  expectError((m) => { m.edges = m.edges.filter((e) => e.relation !== 'under'); }, /^ci-leash: a content idea must sit under a pillar/);
});
