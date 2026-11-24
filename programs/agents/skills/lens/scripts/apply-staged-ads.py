#!/usr/bin/env python3
# Apply staged impressions-ranked ad captures (tmp/competitors/ads-staging/) to the lens in one step.
# Procedure: .claude/skills/lens/competitors.md. DRY=1 checks without writing.
# The lens folder is $LENS_DIR (relative to the repo root), else docs/lens.
# Checks everything first and writes nothing if any check fails. Deletes only files that no ad in
# model.json references, each by its exact path (no wildcards, no shell).
import json, os, shutil, subprocess, sys
R = subprocess.check_output(['git','rev-parse','--show-toplevel'], text=True).strip()
S = f'{R}/tmp/competitors/ads-staging'; L = f"{R}/{os.environ.get('LENS_DIR', 'docs/lens')}"; A = f'{L}/assets/ads'
THEMES = {'social proof','founder story','pain agitation','aspiration','urgency','free trial','comparison','authority','humor','demo'}
# Name products to apply only those (e.g. `apply-staged-ads.py acme`); with none, everything staged.
products = sys.argv[1:] or sorted(f[:-5] for f in os.listdir(S) if f.endswith('.json') and not f.startswith('.'))
staged = {p: json.load(open(f'{S}/{p}.json')) for p in products}
AVATARS = {n['id'] for n in json.load(open(f'{L}/model.json'))['nodes'] if n['kind'] == 'avatar'}

def duration(path):
    out = subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0',path], capture_output=True, text=True)
    try: return float(out.stdout.strip())
    except ValueError: return 0.0

problems = []
for p, d in staged.items():
    ads = d['ads']
    if not ads: problems.append(f'{p}: no ads')
    if sorted(a.get('rank') or 0 for a in ads) != list(range(1, len(ads) + 1)): problems.append(f'{p}: ranks are not 1..{len(ads)}')
    if len({a['id'] for a in ads}) != len(ads): problems.append(f'{p}: duplicate ad ids')
    for a in ads:
        who = f"{p}/{a['id']}"
        if a.get('url') != f"https://www.facebook.com/ads/library/?id={a['id']}": problems.append(f'{who}: url is not its permalink')
        if not str(a.get('text', '')).strip(): problems.append(f'{who}: no text')
        if a.get('image') != f"assets/ads/{p}/{a['id']}.png" or not os.path.exists(f"{S}/{p}/{a['id']}.png"): problems.append(f'{who}: staged still missing or misnamed')
        if a.get('video'):
            v = f"{S}/{p}/{a['id']}.mp4"
            if a['video'] != f"assets/ads/{p}/{a['id']}.mp4" or not os.path.exists(v): problems.append(f'{who}: staged video missing or misnamed')
            elif duration(v) <= 0: problems.append(f'{who}: staged video has no duration')
        an = a.get('analysis') or {}
        if not all(str(an.get(k, '')).strip() for k in ('hook','framing','why')): problems.append(f'{who}: analysis incomplete')
        if not an.get('themes') or not set(an['themes']) <= THEMES: problems.append(f'{who}: themes not from the list')
        if an.get('avatar') not in AVATARS: problems.append(f'{who}: avatar not an avatar id')
if problems or os.environ.get('DRY'):
    print('checked', len(staged), 'products;', len(problems), 'problems')
    print('\n'.join(problems)); sys.exit(1 if problems else 0)

model = json.load(open(f'{L}/model.json'))
by_id = {n['id']: n for n in model['nodes']}
for p, d in staged.items():
    os.makedirs(f'{A}/{p}', exist_ok=True)
    for a in d['ads']:
        shutil.copy2(f"{S}/{p}/{a['id']}.png", f"{A}/{p}/{a['id']}.png")
        if a.get('video'): shutil.copy2(f"{S}/{p}/{a['id']}.mp4", f"{A}/{p}/{a['id']}.mp4")
    keep = ('id','rank','libraryPosition','impressions','url','started','text','headline','cta','image','video','analysis')
    n = by_id[f'pr-{p}']
    n['metaAds'] = {'status': 'active', 'text': d['summary'], 'ads': [{k: a[k] for k in keep if k in a} for a in sorted(d['ads'], key=lambda x: x['rank'])], 'source': d.get('page') or n['metaAds'].get('source')}
json.dump(model, open(f'{L}/model.json', 'w'), indent=2, ensure_ascii=False); open(f'{L}/model.json', 'a').write('\n')

refs = {a[k] for n in model['nodes'] if n['kind'] == 'product' for a in n['metaAds']['ads'] for k in ('image','video') if a.get(k)}
removed = []
for root, _, files in os.walk(A):
    for f in files:
        rel = os.path.relpath(os.path.join(root, f), L)
        if rel not in refs:
            os.remove(os.path.join(root, f)); removed.append(rel)
print(f'applied {len(staged)} products: {", ".join(products)}; removed {len(removed)} unreferenced files')
for r in removed: print('  -', r)
