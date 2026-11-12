#!/usr/bin/env python3
"""Add or replace one competitor product in the lens's model.json from a research JSON.

  python3 .claude/skills/lens/scripts/add-product.py tmp/competitors/<id>.json \
      --alternative <alternative node id> --source <market-research source id> \
      --entry "<short entry price>" --headline "<short revenue headline>" [--lens docs/lens]

The research JSON shape is in .claude/skills/lens/competitors.md. The lens folder defaults to
$LENS_DIR, else docs/lens, relative to the repo root. Run build.mjs afterwards; it validates
everything this writes.
"""
import argparse, json, os, subprocess

root = subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], text=True).strip()
ap = argparse.ArgumentParser()
ap.add_argument('research'); ap.add_argument('--source', required=True)
ap.add_argument('--alternative', required=True, help='id of the alternative (kind) this product is one of')
ap.add_argument('--entry', required=True); ap.add_argument('--headline', required=True)
ap.add_argument('--lens', default=os.environ.get('LENS_DIR', 'docs/lens'))
a = ap.parse_args()
model_path = os.path.join(root, a.lens, 'model.json')
r = json.load(open(a.research))
d = json.load(open(model_path))
ids = {n['id']: n for n in d['nodes']}
if ids.get(a.source, {}).get('kind') != 'source': raise SystemExit(f'--source {a.source} is not a source node')
alt = a.alternative
if ids.get(alt, {}).get('kind') != 'alternative': raise SystemExit(f'--alternative {alt} is not an alternative node')
pid = f"pr-{r['id']}"
owner_src = next((n['id'] for n in d['nodes'] if n['kind'] == 'source' and d.get('owner') in (n.get('people') or [])), None)

def http(u): return isinstance(u, str) and u.startswith('http')
def ads(x):
    return {'status': x['status'], 'text': x['text'], 'ads': [], **({'source': x['source']} if x.get('source') else {})}
rev = r['revenue']; srcs = [u for u in rev.get('sources', []) if http(u)]
node = {'id': pid, 'kind': 'product', 'title': r['name'], 'body': r['summary'], 'url': r['url'], 'research': a.source,
        'pitch': {'quote': r['pitch']['quote'], 'source': r['pitch']['source']},
        'pricing': {'entry': a.entry, 'text': r['pricing']['text'], 'source': r['pricing']['source'], 'checked': r['pricing'].get('checked', '')},
        'revenue': {'headline': a.headline, 'text': rev['text'] if (srcs or rev['text'] == 'Not public') else 'Not public', 'sources': srcs},
        'metaAds': ads(r['metaAds']), 'tiktokAds': ads(r['tiktokAds']),
        'notable': [{'text': x['text'], 'source': x['source']} for x in r.get('notable', []) if http(x.get('source'))],
        'vs': [{'id': f'{pid}-vs', 'text': r['vsUs'], 'kind': 'hypothesis', 'evidence': [{'source': a.source, 'at': r['name']}]}]}
d['nodes'] = [n for n in d['nodes'] if n['id'] != pid]
d['edges'] = [e for e in d['edges'] if e['id'] != f'e-{pid}-is']
d['nodes'].insert(next(i for i, n in enumerate(d['nodes']) if n['id'] == a.source), node)
d['edges'].append({'id': f'e-{pid}-is', 'from': pid, 'to': alt, 'relation': 'is-a',
                   'claim': {'id': f'e-{pid}-is-c', 'text': f"{r['name']} is one of these.", 'kind': 'view',
                             'evidence': [{'source': owner_src, 'at': 'whole source'}]}})
json.dump(d, open(model_path, 'w'), indent=2, ensure_ascii=False); open(model_path, 'a').write('\n')
print(f'{pid} added under {alt}')
