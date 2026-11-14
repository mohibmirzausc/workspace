// build.mjs
// Validate model.json, refuse to build on any error, and inline the components into index.html.
//   node <lens-dir>/build.mjs
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const dir = path.dirname(fileURLToPath(import.meta.url));
const { validate, checkIdContinuity } = require('./components/validate.js');
const Graph = require('./components/graph.js');

// Inline order: each file may use only those before it.
export const ORDER = ['schema.js', 'graph.js', 'ui.js', 'evidence-list.js', 'confidence.js', 'home.js', 'avatars.js', 'surfaces.js', 'alternatives.js', 'marketing.js', 'insights.js', 'decisions.js', 'interviewees.js', 'evidence.js', 'detail.js', 'comments.js', 'app.js'];
const read = (name) => fs.readFileSync(path.join(dir, name), 'utf8');

function fileExistsIn(root) {
  const real = fs.realpathSync(root);
  return (rel) => {
    const abs = path.resolve(root, rel);
    return fs.existsSync(abs) && fs.realpathSync(abs).startsWith(real + path.sep);
  };
}

function images(model) {
  const out = {};
  for (const n of model.nodes.filter((x) => x.image)) {
    const file = path.resolve(dir, n.image);
    if (file.startsWith(path.join(dir, 'assets') + path.sep) && fs.existsSync(file)) out[n.id] = `data:image/png;base64,${fs.readFileSync(file).toString('base64')}`;
  }
  return out;
}

// The last commit date touching each surface's code, so the page can flag screenshots older than it.
function codeDates(model, root) {
  const out = {};
  for (const n of model.nodes.filter((x) => x.kind === 'surface' && x.code.length)) {
    try {
      const date = execFileSync('git', ['log', '-1', '--format=%cs', '--', ...n.code], { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
      if (date) out[n.id] = date;
    } catch { /* not a git checkout: no staleness flags */ }
  }
  return out;
}

// Where code links point: the GitHub repo behind origin, at its default branch as last fetched.
// No GitHub origin means no links (paths are shown as plain text).
function repoInfo(root) {
  const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  let url;
  try {
    url = git('remote', 'get-url', 'origin').replace(/^git@github\.com:/, 'https://github.com/').replace(/^ssh:\/\/git@github\.com\//, 'https://github.com/').replace(/\.git$/, '');
  } catch { return null; }
  if (!/^https:\/\/github\.com\/[^/]+\/[^/]+$/.test(url)) return null;
  // The remote branch, not HEAD: a local commit 404s on GitHub, and HEAD would change index.html on every commit.
  for (const ref of ['origin/HEAD', 'origin/main', 'origin/master']) {
    try { return { url, sha: git('rev-parse', ref) }; } catch { /* try the next */ }
  }
  return { url, sha: 'HEAD' };
}

// The repo root (code and adr paths are relative to it), else the lens folder itself.
export function repoRoot(from = dir) {
  try { return execFileSync('git', ['rev-parse', '--show-toplevel'], { cwd: from, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); } catch { return from; }
}

// Ad videos are gitignored (local playback only), so a checkout may not have them. Drop `video` from
// any ad whose file isn't here, so the card shows its still and library link instead of a dead player.
export function withLocalVideos(model, exists, lensDir = '.') {
  const copy = JSON.parse(JSON.stringify(model));
  for (const n of copy.nodes.filter((x) => x.kind === 'product')) {
    for (const key of ['metaAds', 'tiktokAds']) {
      for (const ad of n[key]?.ads || []) if (ad.video && !exists(lensDir === '.' ? ad.video : `${lensDir}/${ad.video}`)) delete ad.video;
    }
  }
  return copy;
}

export function buildHtml(model, { root, lock }) {
  const lensDir = path.relative(fs.realpathSync(root), fs.realpathSync(dir)).split(path.sep).join('/') || '.';
  const errors = [...validate(model, { fileExists: fileExistsIn(root), lensDir }), ...checkIdContinuity(lock, model)];
  if (errors.length) return { html: null, errors, ids: null };
  const components = ORDER.map((f) => read(path.join('components', f))).join('\n');
  const hash = crypto.createHash('sha256').update(JSON.stringify(model)).update(components).update(read('template.html')).digest('hex').slice(0, 12);
  const shown = withLocalVideos(model, fileExistsIn(root), lensDir);
  const data = JSON.stringify({ ...shown, images: images(model), codeDates: codeDates(model, root), repo: repoInfo(root), lensDir: lensDir === '.' ? '' : lensDir, build: hash }).replaceAll('<', '\\u003c');
  let html = read('template.html');
  for (const [marker, value] of [['/*__DATA__*/', `const D = ${data};`], ['/*__COMPONENTS__*/', components], ['/*__COMMENT_CSS__*/', read('components/comments.css')]]) {
    if (!html.includes(marker)) return { html: null, errors: [`template: missing ${marker}`], ids: null };
    html = html.replace(marker, () => value);
  }
  return { html, errors: [], ids: Graph.createGraph(model).commentableIds().sort() };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const model = JSON.parse(read('model.json'));
  const lockFile = path.join(dir, 'ids.lock.json');
  const lock = fs.existsSync(lockFile) ? JSON.parse(fs.readFileSync(lockFile, 'utf8')) : [];
  const { html, errors, ids } = buildHtml(model, { root: repoRoot(), lock });
  if (errors.length) {
    console.error(`Lens: ${errors.length} problem${errors.length === 1 ? '' : 's'}; index.html not written.\n${errors.map((e) => `  ${e}`).join('\n')}`);
    process.exit(1);
  }
  fs.writeFileSync(path.join(dir, 'index.html'), html);
  fs.writeFileSync(lockFile, `${JSON.stringify(ids, null, 2)}\n`);
  console.log(`Validated ${model.nodes.length} nodes, ${model.edges.length} connections, ${ids.length} commentable ids; wrote index.html.`);
}
