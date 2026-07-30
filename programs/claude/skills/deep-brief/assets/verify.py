#!/usr/bin/env python3
"""
deep-brief verifier — static checks on an assembled brief.

    python3 verify.py ~/html-pages/<date>-<slug>/index.html

Catches the characteristic failures of segmented assembly:
unbalanced tags, broken internal anchors, missing stamp, and
depth below the skill's target. Exits non-zero on failure.

NOTE: this does NOT replace browser testing. Interactive bugs
(dead buttons, handlers destroyed by re-render) are invisible to
static analysis — on the reference brief, `Generate` silently did
nothing and only a real click surfaced it. Serve the page
(`python3 -m http.server`) and click through the form too.
"""
import sys, re, os, json

VOID = {'meta','link','br','hr','img','input','source','col','area',
        'base','wbr','embed','track','param'}

def check(path):
    src = open(path, encoding='utf-8', errors='ignore').read()
    fails, warns, info = [], [], []

    # ---- tag balance (ignore script/style/comments) ----
    body = re.sub(r'<script.*?</script>', '', src, flags=re.S)
    body = re.sub(r'<style.*?</style>', '', body, flags=re.S)
    body = re.sub(r'<!--.*?-->', '', body, flags=re.S)
    stack = []
    for m in re.finditer(r'<(/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*?)(/?)>', body):
        close, tag, _, selfclose = m.group(1), m.group(2).lower(), m.group(3), m.group(4)
        if tag in VOID or selfclose == '/':
            continue
        if not close:
            stack.append(tag)
        elif stack and stack[-1] == tag:
            stack.pop()
        elif tag in stack:
            fails.append(f"tag mismatch </{tag}> (innermost open was <{stack[-1]}>)")
            while stack and stack.pop() != tag:
                pass
        else:
            fails.append(f"stray closing </{tag}>")
    if stack:
        fails.append(f"unclosed tags: {stack}")

    # ---- internal anchors ----
    ids = set(re.findall(r'\bid="([^"]+)"', src))
    for target in set(re.findall(r'href="#([^"]+)"', src)):
        if target and target not in ids:
            fails.append(f"broken internal link: #{target}")

    # ---- depth ----
    words = len(re.sub(r'<[^>]*>', ' ', body).split())
    parts = len(re.findall(r'class="part"', src))
    heads = len(re.findall(r'<h[234]\b', src))
    tables = len(re.findall(r'<table\b', src))
    info.append(f"{words:,} words · {parts} parts · {heads} headings · {tables} tables")
    if words < 6000:
        fails.append(f"only {words:,} words — under 6k means you summarized (target 8k-20k)")
    elif words < 8000:
        warns.append(f"{words:,} words — below the 8k target")
    if parts < 15:
        warns.append(f"only {parts} numbered parts — under 15 usually means too-coarse structure")

    # ---- html-page stamp + sidecar ----
    labels = set(re.findall(r'<dt>(Style|Keywords|Recreate prompt)</dt>', src))
    missing = {'Style','Keywords','Recreate prompt'} - labels
    if missing:
        fails.append(f"stamp missing <dt> label(s): {sorted(missing)} — gallery can't index")
    sidecar = os.path.join(os.path.dirname(os.path.abspath(path)), 'meta.json')
    if not os.path.exists(sidecar):
        fails.append("no meta.json sidecar next to index.html")
    else:
        try:
            meta = json.load(open(sidecar))
            for k in ('title','style','keywords','recreate'):
                if not meta.get(k):
                    warns.append(f"meta.json missing '{k}'")
        except Exception as e:
            fails.append(f"meta.json unparseable: {e}")

    # ---- accessibility / floor ----
    if 'prefers-reduced-motion' not in src:
        warns.append("no prefers-reduced-motion block")
    for img in re.findall(r'<img\b[^>]*>', src):
        if 'alt=' not in img:
            warns.append("an <img> lacks alt text")
            break

    # ---- form sanity, if present ----
    if 'INTAKE-JSON' in src:
        qs = len(re.findall(r'\{\s*id:"', src))
        info.append(f"intake form: ~{qs} questions")
        if qs < 10:
            warns.append(f"only ~{qs} form questions (target 15-25)")
        if 'form-root' not in src:
            fails.append("INTAKE-JSON present but no #form-root container")
        if 'addEventListener("click"' not in src and "addEventListener('click'" not in src:
            warns.append("form buttons may not use event delegation — verify they survive re-render")

    return fails, warns, info


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    target = sys.argv[1]
    if not os.path.isfile(target):
        sys.exit(f"not a file: {target}")
    fails, warns, info = check(target)
    for line in info:
        print(f"  {line}")
    for w in warns:
        print(f"  WARN  {w}")
    for f in fails:
        print(f"  FAIL  {f}")
    print()
    if fails:
        print(f"FAILED ({len(fails)} error(s), {len(warns)} warning(s))")
        sys.exit(1)
    print(f"PASSED ({len(warns)} warning(s)) — now browser-test the form")
