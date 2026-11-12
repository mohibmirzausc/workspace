// diff.mjs
// Show what changed in the lens since a git revision, in place. Review only: it rebuilds
// index.html and then adds a layer to that output, so `node <lens-dir>/build.mjs`
// alone removes it.
//   node <lens-dir>/diff.mjs [rev]    # default HEAD
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const GraphDiff = require('./components/graph-diff.js');
const dir = path.dirname(fileURLToPath(import.meta.url));
export const EMPTY = { schemaVersion: 2, nodes: [], edges: [] };

export function applyReview(html, prev, next, rev) {
  if (html.includes(GraphDiff.MARKER)) throw new Error('index.html already carries a review layer; rebuild first');
  const d = GraphDiff.diffGraphs(prev, next);
  return { html: html.replace('</body>', `${GraphDiff.reviewLayer(d, rev)}</body>`), text: GraphDiff.summary(d, rev) };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const rev = process.argv[2] || 'HEAD';
  execFileSync('node', [path.join(dir, 'build.mjs')], { stdio: 'inherit' });
  let prev = EMPTY;
  try { prev = JSON.parse(execFileSync('git', ['show', `${rev}:./model.json`], { cwd: dir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] })); } catch { /* not in that revision: everything is new */ }
  const next = JSON.parse(fs.readFileSync(path.join(dir, 'model.json'), 'utf8'));
  const file = path.join(dir, 'index.html');
  const { html, text } = applyReview(fs.readFileSync(file, 'utf8'), prev, next, rev);
  fs.writeFileSync(file, html);
  process.stdout.write(text);
  console.log(`Clear with: node ${path.relative(process.cwd(), path.join(dir, 'build.mjs'))}`);
}
