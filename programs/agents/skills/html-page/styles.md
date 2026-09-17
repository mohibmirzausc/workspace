# World Styles — seeds, not a menu

**The style space is the whole world, not this file.** You (the model) know
hundreds of thousands of design styles — movements, eras, regional traditions,
subcultures, mediums, software-era aesthetics, one-off auteur looks. **Reach into
that entire knowledge and pick one.** This file is NOT the list of options. It is
a tiny set of examples whose only job is to *break you out of your defaults* so
you remember how vast the space is.

## Before you pick — MANDATORY recency check

You are bad at "just pick something different" — left to yourself you converge,
especially when the *content* is technical (build pipelines, CVEs, merge queues),
which pulls hard toward blueprint / schematic / dossier / terminal looks. So do
NOT choose from memory. First run this and read the output:

```bash
for d in $(ls -dt ~/html-pages/*/ 2>/dev/null | head -8); do
  grep -o '"style"[^,}]*' "$d/meta.json" 2>/dev/null | head -1
done
```

Then apply these hard rules (not suggestions):

1. **Never repeat a style in the last 8 pages** — not the exact string, and not a
   near-synonym (e.g. "Engineering Blueprint" and "Technical Schematic" are the
   same style; "Security Dossier" and "Redacted Case File" are the same style).
2. **Family cap.** The **technical-utility family** — blueprint, schematic,
   engineering/patent drawing, cyanotype, dossier/case-file, CRT/terminal/console,
   CI-pipeline diagram, transit/wayfinding map — is your default attractor. If ANY
   member of that family appears in the last 5 pages, the **entire family is banned
   for this page.** Pick from somewhere else in the world entirely.
3. When in doubt, deliberately jump to a *different axis*: if recent pages were
   dark/mono/technical, go light/serif/organic/decorative (and vice-versa).

The content does NOT dictate the aesthetic. A CVE report can be an Art Nouveau
botanical plate, a 1960s recipe card, or a Persian miniature — the tension between
dry content and an unexpected style is the whole point.

## How to pick

- **Sample broadly across your whole embedding of styles** and commit to one.
  Different every time. Track what's been used recently (the gallery shows past
  styles) and go somewhere genuinely different.
- **No bias toward safe, no bias toward radical.** The user loves *variety* for
  its own sake. Sometimes a famous mainstream movement; sometimes an obscure
  regional or subcultural look; sometimes something so niche it barely has a name;
  occasionally a comfortable safe one too. Over many pages it should feel like a
  tour of the world, not a rotation of favorites.
- **Invented and hybrid styles are welcome** — fuse two traditions, or render a
  non-design concept (a typeface specimen, a transit map, a botanical plate, a
  cassette j-card, a CRT boot screen) as a page aesthetic.
- **If the user names a style, use it.** ("Make it Bauhaus", "use the notes theme.")
- Whatever you land on, **commit fully** and **stamp it** (see SKILL.md) so the
  user sees what was tried and can recreate it.

## A few seeds (to escape from, not choose among)

These are here only to remind you the space is huge — do NOT treat them as the
menu. The best page is often a style that is NOT on this list. Note how FEW of
these are technical/blueprint looks — that's deliberate. The world is mostly
*not* schematics.

Swiss/International Typographic · Brutalism · Neo-brutalism · Bauhaus · Art Deco ·
Memphis · Vaporwave · Y2K/Frutiger Aero · Editorial/Magazine · Blackletter
broadsheet · Minimalism · Maximalism · Cyberpunk/terminal · Glassmorphism ·
Claymorphism · Skeuomorphism · Atompunk · Art Nouveau · Constructivist ·
Soviet/Polish poster · Bengali/Devanagari letterpress · Risograph print · Zine
photocopy · Brutalist concrete · Ukiyo-e woodblock · Mexican lotería card ·
Persian miniature · West-African Adinkra · 8-bit/PETSCII · ASCII teletext ·
Bru­talist Web 1.0 · Pharmacy/apothecary label · Vintage botanical plate · Blueprint
schematic · Transit-map diagram · Brutalist museum signage · Dieter Rams product ·
Vignelli grid · Acid graphics/rave flyer · Solarpunk · Cottagecore · Dark academia ·
Brutalist terminal-green · Cassette-futurism · Lo-fi anime UI · …and the thousands
this list will never name.

## The one fixed entry: Notes (earth-tone)

This single style maps to bundled assets, so it's special. When chosen (at random
or by name as "notes theme"), use the bundled `lib/` instead of inline CSS — see
SKILL.md "Notes theme". Keywords: parchment · serif · skim-first · LLM review doc.

## Interactivity patterns (content-fit, then stamped)

Interactivity is a **content-fit** decision, NOT a random roll. Pick what serves
the content; static is a valid, deliberate choice when interaction adds noise.
This list, unlike the styles above, is genuinely a small menu — but invent new
patterns freely too. Stamp whichever you pick.

| Pattern | When it fits |
|---------|--------------|
| Static text only | Reference/reading content where interaction is noise |
| Checkboxes / todo list | Actionable items, acceptance criteria |
| `<details>` accordions | Long appendices, optional depth, FAQs |
| Tabs (CSS `:checked` / radio) | Parallel alternatives the reader switches between |
| Form inputs | Capturing structured input, calculators |
| Hover reveals / tooltips | Definitions, annotations, progressive disclosure |
| Filter/sort controls | Tables or lists the reader interrogates |
| Copy-to-clipboard buttons | Code snippets, commands |
| Scroll-triggered reveals | Narrative/long-form where pacing matters |
