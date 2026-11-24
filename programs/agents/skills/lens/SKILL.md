---
name: lens
description: Set up and maintain a product lens — one git-tracked JSON graph of a product's purpose, core loop, avatars, interviewees, evidence, claims (Heard / seen · Owner's view · Untested), focus hypotheses with computed confidence, shipped surfaces and ideas, alternatives and competitors, market insights, content pillars and decisions — built into one self-contained, commentable index.html with a diff view. Use when asked to create a lens, add an interview or other evidence, update a surface after changing it, add an idea from a brainstorm, add a competitor, or show what changed in the lens.
---

# Lens

A lens is one JSON graph, `<lens>/model.json`, built into a self-contained `<lens>/index.html`
that anyone can open and comment on. `<lens>` is the folder it was scaffolded into (default
`docs/lens`). `<lens>/README.md` documents the node kinds, relations, claim shape and integrity
rules. The build refuses a model that breaks a rule, so a green build is the first check.

This skill's own folder holds `template/` (what gets copied into a repo), `scripts/` (competitor
helpers) and `competitors.md`. Find it at `.claude/skills/lens/` in the repo, or
`~/.claude/skills/lens/` when installed globally; below, `$SKILL` means that folder.

Requirements: Node 20+ and git. No `package.json`, no dependencies.

## Set up a new lens

1. **Pick the folder.** Ask the user where the lens should live; default `docs/lens`. Refuse to
   overwrite an existing `model.json` there.
2. **Copy the template** (everything except a built `index.html`):

   ```bash
   mkdir -p docs/lens && cp -R "$SKILL/template/." docs/lens/ && rm -f docs/lens/index.html
   echo '[]' > docs/lens/ids.lock.json      # the starter's ids are not yours; start the lock empty
   ```

3. **Interview the user, then replace the starter model.** `model.json` ships with a fictional
   "Acme Notes" example that shows every common kind. Keep its shape, replace its content. Ask, one
   topic at a time, and give a concrete draft to correct rather than a blank question:
   - the product's name (`title`) and the owner's name (the `owner` person node, id `p-owner`
     unless they prefer another; its `title` is shown as "<Name>’s view" on every view claim);
   - the purpose in one sentence (`purpose`, a `view` claim citing the owner's source);
   - the core loop, 2–5 ordered `loop-step`s;
   - who it is for (`avatar`s, with a persona map), and what hurts (`problem`s);
   - interviews or other evidence they already have (`source` + `person` nodes; never invent quotes
     or timestamps — if there is no transcript, record it as the owner's report);
   - what has shipped (`surface`, `shipped: true`, with a real screenshot) and what is only an idea
     (`shipped: false`);
   - what people use instead (`alternative`s);
   - up to three bets to prove now (`hypothesis` nodes with `focus: 1|2|3`).
   Everything the user says without evidence is a `view` (theirs) or a `hypothesis`; nothing is
   `observed` without a source and an `at`. Use placeholder names ("Interviewee A") unless the user
   wants real names in a file that may be public.
4. **Clean up the example.** Delete `assets/example.png` once no node references it, and point
   screenshots at `assets/surfaces/<surface-id>/<slug>.png`. Surface `code` and `adrs` paths are
   relative to the repo root and must exist (point `adrs` at wherever the repo keeps decision
   records, e.g. `docs/adr/`).
5. **Build and test:**

   ```bash
   node docs/lens/build.mjs && node --test docs/lens/tests/*.test.mjs
   ```

6. **Look at it.** Comments are stored in the browser per origin, so serve it rather than opening
   the file directly:

   ```bash
   python3 -m http.server 8767 --bind 127.0.0.1    # from the repo root
   open "http://127.0.0.1:8767/docs/lens/index.html"
   ```

7. Suggest a `.gitignore` line for `docs/lens/assets/ads/**/*.mp4` if they will track competitor
   ads. Commit `model.json`, `ids.lock.json`, `index.html`, `assets/` and the rest of the folder,
   following the repo's own commit rules.

## Ground the work

Read the relevant nodes, their claims and their sources before asking the owner anything. Give
them a concrete synthesis to correct. For a surface, check the code it names (`code`, `adrs`) when
its behaviour matters; a decision record says what was decided, not what the code does today.

## Adding evidence

Every statement is a claim with `kind`, `evidence` and an optional `next`:

- **observed** (Heard / seen): what someone said or did. Cite the source with `at` (a transcript
  timestamp, or a section for a document). Quote or paraphrase closely; never upgrade a hedge
  ("could be useful").
- **view** (Owner’s view): the owner's interpretation. It must cite a source whose `people`
  include the model's `owner`.
- **hypothesis** (Untested): anything untested, including agent suggestions and implementation ideas.
- A hypothesis is also a node kind: log each piece of evidence with `stance` (`supports` or
  `contradicts`) and `at`. Never set a confidence; the meter on the `focus` hypotheses is computed
  from that evidence on the next build (distinct interviewees supporting it; one step down if
  anyone contradicts it; the owner's view never raises it). Log contradicting evidence as readily
  as support.
- Give every weak claim a `next`: a question specific enough to ask in a call. It appears in
  **Next conversation**.
- Keep who said it straight: an idea the owner raised and someone agreed to is not their need.
- A new interview is a `source` with `date`, `people`, `locator` and short `takeaways`, cited by
  the claims it supports. Leave out personal details unrelated to the product. Archive transcripts
  under `<lens>/sources/` only if the repo is private and the interviewee agreed.

## Update a surface (after changing it)

When a change alters what a surface looks like or does, in the same branch:

1. Capture the changed state(s) from the running product into
   `<lens>/assets/surfaces/<surface-id>/<slug>.png` (replace stale ones, keep 1–4).
2. Update the surface's `screenshots` entries: `caption`, `capturedAt` (today), `origin: "app"`,
   `version`. The page flags any screenshot older than the last commit to the surface's `code`.
3. Update `unique` / `situations` if the behaviour changed, and `code` / `adrs` if files moved.

A brand-new shipped surface is a new `surface` node with `shipped: true`, at least one screenshot,
`serves` edges to the problems it addresses and `implements` edges to loop steps.

## Add an idea (from a brainstorm)

A surface that has been discussed but not built is a `surface` with `shipped: false`; it appears
under **Ideas**, visually distinct. Give it `unique` (as `hypothesis` claims), `situations`,
`heard` (what people said, with evidence), and mockups as `screenshots` with `origin: "design"`.
When it ships, flip `shipped` and replace mockups with real captures.

## Add a content pillar or idea

A marketing theme is a `pillar`; a concrete post, video or event is a `content-idea` `under` it,
with a `format`. Link pillars or ideas `speaks-to` avatars, ideas `features` the surfaces they show
and `like` competitors already running a similar angle. Ideas and pillars are Untested until the
content has reached people; log what happened as evidence on a hypothesis `about` the idea.

## Add a market insight

A trend from outside research is an `insight` on the Market insights tab. Record the article as a
`Market research` source (optionally a snapshot under `sources/`), state its facts as observed
`findings`, and keep what it means for an avatar as a view or hypothesis, including a finding on
the source's limits. Link it `bears-on` everything it affects.

## Add or refresh a competitor

Follow `$SKILL/competitors.md`: research (real-browser ad checks, never evading a wall),
`scripts/add-product.py`, staged ad capture, `scripts/apply-staged-ads.py` (checks everything, then
applies in one step), `scripts/smoke-ads.mjs`, then commit without `.mp4`s. Compare with the
product from the lens's purpose and focus hypotheses, never its marketing page, and label that
comparison Untested.

## Usability findings are not lens content

Interaction problems (a button nobody finds, a missing focus state) belong in the team's issue
tracker. File them there and record only their product meaning, if any, in the lens.

## Renaming or removing

`ids.lock.json` records every commentable id from the last build. An id that disappears must be
mapped in `model.json`'s `renamed` (`"old-id": "new-id"`, or `null` when removed on purpose), or
the build fails. This is what keeps existing comments attached.

## Changing the lens itself

Any change under `components/` (what a view shows, routing, validation, the diff) starts with a
failing test in `<lens>/tests/` (`node:test`; shared fixture in `tests/fixture.mjs`, fictional
names only). Keep logic in pure modules; only `components/app.js` touches the DOM. Then run the
tests, then check the same scenario in a browser.

## Visualize the diff

When the owner asks to see, review or visualize what changed:

```bash
node docs/lens/diff.mjs [rev]          # default HEAD; prints the change list
python3 -m http.server 8767 --bind 127.0.0.1
open "http://127.0.0.1:8767/docs/lens/index.html"
```

Green outlines are added items and yellow are changed ones; removed items are listed in red in the
banner. Each added or changed row links to its item. Changes are matched by id, so a single claim
lights up without its whole card. Before committing, always clear it and check:

```bash
node docs/lens/build.mjs
grep -c LENS-V2-DIFF docs/lens/index.html   # must print 0
```

## Rebuild and check

```bash
node docs/lens/build.mjs && node --test docs/lens/tests/*.test.mjs
```

Then look at the affected views in the browser. Comments are browser-local to the origin; export
them before switching. End with the lens link, what changed, the evidence and any limits.
