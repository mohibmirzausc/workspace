# Lens

The owner's working model of the product: what it is for, who it serves, what the evidence says and
doesn't, and what to ask next. Written for a reader who wasn't in the research, with the working
tools (evidence, comments, Next conversation) underneath.

Run from the repo root (paths below assume the lens lives in `docs/lens`):

```bash
node docs/lens/build.mjs                    # validate model.json, write index.html + ids.lock.json
node docs/lens/diff.mjs [rev]               # outline what changed since rev (default HEAD)
node --test docs/lens/tests/*.test.mjs      # every component, plus this lens's model
```

## Files

| File | Role |
| --- | --- |
| `model.json` | The one graph: `title` (the product's name), `owner`, `purpose`, `renamed`, `nodes`, `edges` |
| `build.mjs` | Validates, checks id continuity, inlines components into `template.html` |
| `diff.mjs` | Diff against a git revision, rendered in place |
| `ids.lock.json` | Commentable ids at the last build |
| `components/` | Pure modules (schema, graph, validate, views, detail, diff); `app.js` is the only DOM code |
| `tests/` | `node:test` suites; `fixture.mjs` is the shared valid model |
| `sources/`, `assets/` | Archived evidence (optional), screenshots, avatar art and ad stills |

## Views

Home (purpose, the three focus hypotheses with confidence meters, the loop, other hypotheses) ·
Avatars · Surfaces (shipped) · Ideas (not built) · Alternatives · Marketing · Market insights · Interviewees · Evidence ·
Decisions. Selecting a node, claim or connection opens one detail panel. View keys (`overview`,
`product`, `people`, `sources`, `decisions`) are part of comment anchors, so they don't change.

## Node kinds

`loop-step`, `avatar`, `person`, `problem`, `surface`, `alternative`, `hypothesis`, `source`,
`question`, `decision`, `channel`, `pillar`, `content-idea`, `insight`. Fields per kind are in `components/schema.js`; any other field fails the build.

## Claims

The badge says where a statement comes from: **Heard / seen** (`observed`: someone said or did it;
the evidence is one click away), **<Owner>’s view** (`view`, labelled with the `owner` person's title), **Untested** (`hypothesis`).

```json
{ "id": "…", "text": "…", "kind": "observed | view | hypothesis",
  "evidence": [{ "source": "s-interview-a", "at": "30:07" }], "next": "…?" }
```

## Hypotheses and confidence

A `hypothesis` node holds `evidence: [{ source, at, stance: "supports" | "contradicts", note? }]`,
optional `next: [questions]`, `group: "trust"` and `focus: 1 | 2 | 3`. Only focus hypotheses show
a meter, computed by `components/confidence.js`: distinct interviewees supporting it (0 untested,
1 weak, 2 emerging, 3+ strong), one step down if anyone contradicts it, and *contested* when as
many people contradict as support. The owner's view never raises it.

## Products (competitors)

A `product` is a named competitor, linked `is-a` to the kind of `alternative` it represents. It carries
`url`, `research` (the market-research source it came from), `pitch {quote, source}`, `pricing {entry,
text, source, checked}`, `revenue {headline, text, sources}` (`"Not public"` needs no source),
`metaAds` / `tiktokAds {status: active|none|blocked|not-covered, text, ads[{hook, angle}], source}`,
`notable [{text, source}]` and `vs` (claims, normally Untested). Every market fact carries a URL. The
Alternatives page counts advertisers from these fields, so its headline stays current.

## Marketing

The Marketing tab lists content `pillar`s (a theme the content returns to, with a `claim` for why it
should work) and the `content-idea`s under each (`format`, `claim`). Every content idea must sit `under`
a pillar, or the build fails. Link ideas to the surfaces they show and to competitors running a
similar angle (`like`); a channel is still where an avatar is reached, not what the content says.

## Market insights

An `insight` is a takeaway from outside research (news, reports, surveys): `findings` are claims, so
what the source says stays Heard / seen and what it means for the product stays the owner’s view
or Untested. It links `bears-on` to any avatar, problem, pillar, hypothesis, channel or person. Archive
the article itself as a `Market research` source with a snapshot.

## Surfaces

`surface` carries `unique`, `situations` and `heard` (claims; heard is shown newest first),
`code`, `adrs` (paths relative to the repo root, e.g. into `docs/adr/`), `shipped`, and `screenshots: [{ file: "assets/surfaces/<id>/<slug>.png", caption,
capturedAt: "YYYY-MM-DD", origin: "app" | "design", version? }]`. A shipped surface needs at least
one screenshot. The build flags a screenshot older than the last commit touching the surface's
`code`. `shipped: false` surfaces are Ideas. A card shows **Code** (`code` paths, as GitHub permalinks at
the remote default branch when `origin` is a GitHub repo, else plain paths) and **Decisions** (`adrs` as links, plus lens decisions that `shape` it) separately.

## Relations

person —fits→ avatar · avatar —has→ problem · person —reports→ problem · surface —serves→ problem ·
surface —implements→ loop-step · surface —depends-on→ surface · question —tests→ any · decision
—shapes→ any · avatar —may-reach-through→ channel · alternative —also-serves→ problem · hypothesis
—about→ any · content-idea —under→ pillar ·
pillar / content-idea —speaks-to→ avatar · content-idea —features→ surface (shown as “Shows”) ·
content-idea —like→ product · insight —bears-on→ any. Every edge
carries a claim.

## Integrity rules

1. Ids are unique across nodes, edges and claims, and lowercase-kebab.
2. Every reference resolves.
3. Each kind has exactly its fields.
4. An observed claim cites evidence with `at`.
5. A view claim cites a source by the `owner`.
6. Hypothesis evidence has a stance and `at`; each focus slot is used once.
7. A relation must be allowed for its kind pair.
8. Surface `code`, `adrs` and screenshot files exist; shipped surfaces have a screenshot.
9. No orphans: every node is connected and every source is cited.
10. Loop steps are ordered 1..n.
11. Sources have one tag, a valid date and snapshots under `sources/`.

A commentable id that disappears needs a `renamed` entry, or the build fails.
