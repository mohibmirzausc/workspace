// tests/build.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { fixture, clone } from './fixture.mjs';
import { buildHtml, ORDER, withLocalVideos } from '../build.mjs';

const dir = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const opts = { root: dir, lock: [] };

test('a valid model builds with every component inlined and no marker left', () => {
  const { html, errors } = buildHtml(fixture, opts);
  assert.deepEqual(errors, []);
  for (const m of ['/*__DATA__*/', '/*__COMPONENTS__*/', '/*__COMMENT_CSS__*/']) assert.ok(!html.includes(m), m);
  for (const file of ORDER) assert.ok(fs.existsSync(path.join(dir, 'components', file)), file);
  assert.match(html, /const Home = /);
  assert.match(html, /"codeDates":\{/);
});

test('an invalid model returns errors and no html', () => {
  const m = clone(fixture);
  m.edges[0].relation = 'serves';
  const { html, errors } = buildHtml(m, opts);
  assert.equal(html, null);
  assert.ok(errors.some((e) => e.startsWith('e-alpha-fits:')));
});

test('a vanished id without a renamed entry fails the build', () => {
  const { errors } = buildHtml(fixture, { ...opts, lock: ['x-old'] });
  assert.ok(errors.some((e) => e.startsWith('x-old:')));
});

test('the data block escapes "<" so a claim cannot close the script', () => {
  const m = clone(fixture);
  m.nodes.find((n) => n.id === 'n-focus').body = '</script><b>';
  assert.ok(!buildHtml(m, opts).html.includes('</script><b>'));
});

test('an ad whose video is not on this machine loses its video, so the card shows the still and link', () => {
  const m = clone(fixture);
  const ad = m.nodes.find((n) => n.id === 'pr-acme').metaAds.ads[0];
  const missing = withLocalVideos(m, () => false).nodes.find((n) => n.id === 'pr-acme').metaAds.ads[0];
  assert.equal(missing.video, undefined);
  assert.equal(missing.image, ad.image);
  const present = withLocalVideos(m, (p) => p === 'assets/ads/pr-acme/123.mp4').nodes.find((n) => n.id === 'pr-acme').metaAds.ads[0];
  assert.equal(present.video, 'assets/ads/pr-acme/123.mp4');
  assert.equal(ad.video, 'assets/ads/pr-acme/123.mp4', 'the model itself is not changed');
});

test('the built page never points a player at a missing video', () => {
  const { html } = buildHtml(fixture, opts);
  assert.ok(!html.includes('assets/ads/pr-acme/123.mp4'));
});
