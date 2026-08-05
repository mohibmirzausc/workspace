---
name: obsidian-vault-engineering
description: Use when working on an Obsidian vault that syncs via git (obsidian-git) across desktop + mobile — especially merge-conflict resolution, Templater/dataviewjs automation, mobile isomorphic-git internals, and the mobile JS footguns that crash dataviewjs. Covers the union-merge auto-resolver architecture and a local mock-git test harness.
---

# Obsidian Vault Engineering (git-synced, desktop + mobile)

## Overview

Hard-won knowledge for engineering a git-synced Obsidian vault — the kind published/backed-up
via the **obsidian-git** plugin and synced to a phone. The central, non-obvious fact that
drives almost everything below:

> **obsidian-git uses TWO DIFFERENT git engines.** DESKTOP uses `simple-git` (shells out to
> native git; manager class `Ce`). MOBILE uses **isomorphic-git** (pure JS; manager classes
> `wn`/`Vi`). They behave differently in ways that break naive assumptions — the mobile engine
> ignores merge drivers, hardcodes some status fields, strips exec bits, and can't cancel
> in-flight network ops.**

If you don't internalize the desktop/mobile split you will waste enormous time debugging
"works on desktop, broken on phone" mysteries. Most of this skill is about the mobile side.

## When to use

- Building/debugging an obsidian-git sync setup that spans desktop + mobile.
- Writing Templater startup scripts, `dataviewjs` dashboards, or any in-vault JS automation.
- Resolving mobile merge conflicts / "you have unmerged files" / "Initializing push" hangs.
- Anytime you're about to edit JS that runs inside Obsidian **on a phone** (iOS especially).

## The debugging meta-lesson (read first)

You usually **cannot run the code yourself** — it runs inside Obsidian on a phone you can't
inspect. This makes blind iteration brutally slow (we did ~15 phone round-trips before getting
it right). Two force-multipliers:

1. **Read the plugin source.** `.obsidian/plugins/obsidian-git/main.js` is minified but
   greppable. `grep -oE 'async methodName\([^)]*\)\{.{0,300}'` reveals exact behavior. Don't
   guess what a method does — read it. This is how every real bug below was found.
2. **Build a mock harness** (see "Local test harness"). Model the plugin's gitManager in Node
   and test your logic in milliseconds. Validate BEFORE the phone round-trip.
3. **Log to a file, not the console.** Mobile has no console and Notices vanish. Write a
   timestamped append-only log to a `.md` NOTE, add a "Copy to clipboard" button, read it on
   desktop after it syncs. This is the only real observability you get.

## Mobile isomorphic-git: the landmines

### `status().conflicted` is ALWAYS `[]` on mobile
The isomorphic-git manager hardcodes `conflicted: []` — only desktop's simple-git populates it.
**Detect conflicts via the `"U"` flag on `status().all` entries** (`index==="U" || workingDir==="U"`),
which BOTH engines set. Also scan `.md` files for literal `<<<<<<<`/`>>>>>>>` markers (isomorphic
sometimes writes markers but leaves the index as `M`, not `U`). Union of all three signals.

### The conflict manifests as a helper NOTE, not your edited file
On a real conflict the phone's plugin writes `conflict-files-obsidian-git.md` (flagged `U`, and
it literally embeds `<<<<<<< HEAD ... ======= ... >>>>>>>` sample text). Your actually-edited
note often shows as plain `M`. Detection + healing must target the helper note too.

### Merge drivers are ignored; `mergeStrategy: "ours"` is a NO-OP
`.gitattributes` `*.md merge=union` works on desktop, NOT mobile. Mobile pull calls
`merge({ours, theirs, abortOnConflict:false})` where ours/theirs are just branch refs, not a
favor preference. There is no user-facing conflict-favor setting; `mergeStrategy` in data.json
is legacy/ignored. `abortOnConflict:false` is why the phone writes markers and gets stuck.

### `push()` can't be cancelled; timeouts race
isomorphic-git `push()` shows `showNotice("Initializing push")` and has no cancellation. A
`Promise.race([push, timeout])` "timeout" leaves the real push RUNNING in the background. If
you then start a pull, two ops race on the same `.git` → corruption + multiple "Initializing
push" notices ("stuck on push"). NEVER act on a timeout as if the op failed cleanly — stop, let
the next quiescent pass retry.

### There is NO `git reset --hard <ref>`, and reset is HARDER than it looks
The mobile manager exposes `status`, `branchInfo`, `fetch`, `resolveRef`, `checkout(branch,
remote)`, `discard(path)`, `deleteBranch`, `createBranch` — but no hard-reset-to-ref. **Do NOT
assume `checkout(branch, remote)` resets to remote — it does NOT move the branch pointer.** When
`branch` exists locally, `checkout(branch, remote)` only *cleans the working tree* and switches;
the local branch ref stays on the diverged commit (a "clean tree" can still be `diverged:true`).
And `checkout(sha)` with no 2nd arg has `force = !!undefined = false` → won't move a diverged
head either. The **working reset ladder** (verify each step by re-reading HEAD vs remote SHA):
1. `checkout(remoteSha, true)` — force-detach HEAD onto the remote commit (moves head + cleans tree).
2. If the branch ref is still on the old commit: `deleteBranch(main)` then `checkout(main, remote)`
   — with `main` now absent, checkout *recreates* it AT the remote SHA and re-attaches. (This is
   the reliable ref-mover; `checkout(branch, remote)` creates-from-remote only when the branch is
   absent, otherwise it just switches.)

Always confirm success by comparing `resolveRef("HEAD")` to `resolveRef(tracking)` — NOT by a
clean working tree. Checking only "tree empty" will report a false success on a stranded commit.

### The plugin's own "Discard all changes" SKIPS conflicted files
Mobile `discardAll()` filters `a.workingDir != "U"` — it refuses to touch the exact conflicted
file keeping you stuck. Roll your own: `gitManager.discard(path)` (= force-checkout one file to
HEAD) works on `U` files. For a full reset use the ladder above.

### force-push is not reachable — and remote-wins is the safe default
The plugin's mobile `push()` doesn't expose `force`, and the raw isomorphic-git lib isn't
reachable from the dashboard (`re.default` is module-internal; no global handle). Don't try to
force-push. It's also dangerous with 3 writers on `main` (could clobber desktop commits). Default
to **remote-wins** (reset-to-remote). For **phone-wins WITHOUT force-push**: capture the phone's
edit → reset onto remote (ladder above) → re-apply the edit → commit → **normal fast-forward
push**. Phone content lands on remote, remote history preserved as ancestor — no clobber.

**Capture must cover COMMITTED edits, not just the working tree.** The phone's auto commit-and-sync
often commits the edit before you tap phone-wins, leaving a `diverged-clean-tree`: HEAD diverged
but `status().all` empty. Capturing only from `status().all` then finds nothing and the reset
erases the edit (this bug silently lost data until 2026-08-01). Fix: also diff committed HEAD vs
remote via the manager's public `getFileChangesCount(remoteSha, HEAD)` (returns `[{path,type}]`
from a two-TREE `walk`, no working-tree dependency), union those paths with `status().all`, and
`vault.read` each — `vault.read` returns the on-disk (= phone's) content regardless of git state.
The mobile manager exposes `resolveRef`/`branchInfo`/`getFileChangesCount`/`checkout`/`deleteBranch`
publicly; the raw `re` handle stays private, so prefer these over reaching for isomorphic-git directly.

### Three writers race on `main` — and `setPausedAutomatics` does NOT fully stop it
The resolver, obsidian-git's auto commit-and-sync, and pull-on-boot all commit/pull/push
independently. `autoSaveInterval` is in **MINUTES** (`*60000`). **DO NOT rely on
`setPausedAutomatics(true)` to serialize** — it only sets a localStorage flag that's checked when
timers are ARMED (boot / `reload()`), NOT inside the running `doAuto*` callbacks, and the vault
file-watcher's `autoCommitDebouncer` ignores it entirely. To truly stop the plugin's automation you
must call `plugin.automaticsManager.unload()` (clears all timers + the debouncer). **The reliable
fix is to make the plugin PASSIVE via settings** (see the next section) so your script is the sole
driver. `git.localStorage.getConflict()` gates the plugin's own commit ("Did not commit, because
you have conflicts").

## Plugin internals that FIGHT an external driver (source-audit findings — read before driving git)

Reverse-engineering `main.js` (mobile mgr class `wn`; AutomaticsManager `Bc`; serial `PromiseQueue`
`fh`) surfaced why an external script driving the mobile manager keeps hitting loops. All verified:

- **`pull()` throws `MissingParameterError` ('requires a "ref"') on a detached HEAD or lost upstream.**
  It runs `merge({ours:branchInfo().current, theirs:branchInfo().tracking})` then
  `checkout({ref:branchInfo().current,...})`. Detached HEAD ⇒ `current` undefined; lost upstream ⇒
  `tracking` undefined ⇒ the error + obsidian-git's "which branch?" / "set upstream branch" prompt.
  `canPush()` shares the unguarded `resolveRef(undefined)` (unlike `getUnpushedCommits`, which
  null-guards). **So: NEVER leave HEAD detached or upstream unset.**
- **`checkout(<bareSHA>, true)` DETACHES HEAD** (`re.checkout({ref:sha, force:true, remote:true})`).
  If your reset ladder force-checks-out a remote SHA to move a diverged head, HEAD is now detached —
  which is tree-clean AND head==remote, so a naive "converged?" check passes and the ladder stops
  there, stranding a detached HEAD. **Convergence MUST also require HEAD attached** (detect via
  `branchInfo().current === undefined`); if detached, run delete-branch + `checkout(branch, remote)`
  to RE-ATTACH.
- **mobile `commit()` reads `getConflict()`; if set it forces `parent:[current,tracking]`.** On a
  detached/untracked HEAD those are undefined → throws or writes a malformed 2-parent commit, and the
  flag clears only on success → infinite bad-commit loop. **After any reset: `setConflict(false)` AND
  `plugin.updateCachedStatus()`** (mobile re-derives from the always-`[]` `status().conflicted`, which
  clears the flag).
- **`updateUpstreamBranch()` secretly PUSHES on mobile** (`re.push({remoteRef})` then sets config). Do
  NOT call it to "restore tracking" — it triggers the uncancellable push and a "set upstream branch"
  prompt loop. Restore lost tracking manually (the plugin's "Set upstream branch" command) or re-clone.
- **`push()` has no abort/timeout/signal.** A wedged push hangs the plugin's serial `PromiseQueue`
  forever while the file-watcher + independent pull/push timers keep enqueuing → "Initializing push"
  loop. Your `withTimeout` stops YOU waiting, not the push. Mitigate with a **boot-loop guard**: persist
  a `lastPushAttemptAt` timestamp to localStorage before the push leg; on a boot within ~90s, SKIP the
  push (local resolve still runs) so a wedge can't re-fire every launch. Clear it on a confirmed clean
  push/reset.
- **P0 RACE: pull-on-boot fires on the SAME `onLayoutReady` as a Templater startup script, no shared
  lock.** The `PromiseQueue` serializes only the plugin's OWN ops, not your direct `gitManager` calls.
  Concurrent `.git`/index mutation ⇒ the detached-HEAD state.

**Operational fix (phone settings) — make the plugin PASSIVE:** Pull-on-startup OFF, Auto
commit-and-sync 0, Auto push 0, Auto pull 0, Commit-after-file-change OFF. Then the resolver+dashboard
are the sole driver; incoming = resolver pulls on boot (or a Pull button), outgoing = a deliberate
Commit&sync / phone-wins tap. This is the trade that finally made mobile git stable.

**Log for diagnosis-from-one-paste:** tag every verbose line with a per-run id so interleaved passes
are separable; promote `DETACHED`/`NO-UPSTREAM` to first-class snapshot verdicts (not buried fields);
emit a `boot` anchor event (guard state + age of last push attempt) so across-restart loop behavior is
readable; keep dumps to numbered marker LINES, not whole file bodies (mobile log is line-capped).

## The union-merge auto-resolver architecture (what actually works)

A Templater **startup template** that, on boot, detects mobile conflicts and heals them. The
end-to-end validated design:

1. **Re-entry guard** (window flag + timestamp cooldown) — Templater can re-invoke the startup
   template; a plain flag isn't enough. Also a **generation-token guard** (`runToken`/`release()`)
   so a watchdog force-clear can't spawn a second concurrent pass; watchdog timeout must exceed
   the max single-pass time.
2. **FAST IDLE PATH** — read `status()` first; if no `U`/marker, return writing NOTHING. Per-pass
   log writes churn Dataview and make the app "phase in and out." Only real-conflict passes log.
   Cap the log to ~200 lines on every write (unbounded growth slows every read → thrash).
3. **Detect** via U-flag + markers (see above). **Union-resolve** each hunk (keep both sides,
   de-duped). Stage via `git.stageFile(tfile)`.
4. **Commit + ONE bounded push** (30s timeout). Do NOT loop pull→push (that loop caused the
   "stuck on Initializing push" + churn).
5. **On non-fast-forward rejection → RESET TO REMOTE** (this is THE fix for the infinite
   re-divergence loop): pause automatics, delete the conflict note, clear the conflict flag,
   `checkout(branch, remote)`, verify `status().all` is empty, resume automatics in `finally`.
   Remote wins; the stranded local commit is discarded; nothing re-creates the divergence.

**Why reset-to-remote and not force-push:** force-push works (`push({force:true})`) but makes the
phone OVERWRITE remote — risks clobbering other devices' commits. Default to remote-wins (no data
loss on the remote side); the phone's edit is lost only if it can't re-apply on the new base.

**The re-divergence loop was the root cause of "even Discard ALL doesn't work":** discard cleans
the tree, but if a stranded local commit survives, the next auto-backup/scheduled pass re-pulls →
re-conflicts → re-commits → rejected forever. The reset-to-remote (in BOTH the resolver and the
discard button) is what breaks it.

## Mobile dataviewjs / JS footguns (each one crashes the WHOLE block)

iOS JavaScriptCore (Capacitor WebView) is stricter than desktop Electron. These are PARSE/eval
crashes shown as `eval@[native code]` + a `capacitor://localhost/app.js` stack:

- **Emoji inside a regex character class** `/[🔺⏫]/u` → SyntaxError at parse. Use string
  alternation `/🔺|⏫/` with NO `u` flag.
- **Backticks inside a comment that's inside a template literal** → closes the string early →
  `SyntaxError: Unexpected identifier`. Keep backticks out of CSS-template comments.
- **Assigning `window.__x.foo = ...` before `window.__x = window.__x || {}`** → `undefined.foo =`
  TypeError → whole dataviewjs block dies. Initialize the namespace FIRST.
- **`.DS_Store` (or any indexed-but-absent file)** → mobile `status()` throws `ENOENT lstat` →
  resolver bails silently. Gitignore `.DS_Store` + `**/.DS_Store`.

**Verification before every push:** count braces/parens/backticks with `//` COMMENTS STRIPPED
(comment parens/backticks give false mismatches). Scan for emoji-in-charclass regexes. Example:
```python
code_nc = "\n".join(re.sub(r"//.*$","",l) for l in code.split("\n"))
# braces/parens must balance; backticks should be exactly the template-literal count
```

## What must / must NOT sync (gitignore policy)

- **MUST stay tracked:** plugin binaries `.obsidian/plugins/*/main.js` + `styles.css`. Mobile
  obsidian-git does NOT install from the community store — the phone gets plugins ONLY from the
  repo. Gitignoring `main.js` DELETES the plugin on the phone's next pull (breaks everything).
- **MUST be gitignored (per-device / secret / churn):**
  - `.obsidian/community-plugins.json` — rewritten on any toggle, mobile can't union-merge JSON,
    silently toggles plugins OFF cross-device (blanks dashboards). Untrack per-device.
  - `_Experiments/union-resolver*.log.md` — every device appends every boot → self-conflicts.
  - `.obsidian/plugins/obsidian-local-rest-api/data.json` — contains a TLS private key + apiKey.
  - `.DS_Store`, `**/.DS_Store` — crashes mobile `status()`.
  - `quartz-site/` (or any SSG/node_modules) — bloats the repo the phone must carry.
  - `tools/` — local-only dev harness (see below).

## Local test harness (the accelerator)

Mock obsidian-git's mobile gitManager in Node so resolver/discard logic runs in milliseconds
instead of phone round-trips. Model: `status()` returning `{all:[{path,index,workingDir}],
conflicted:[]}`; `push()` throwing "not a simple fast-forward" unless local is a fast-forward of
remote (or `{force}`); `checkout(branch,remote)` = reset local head+tree to remoteHead;
`discard(path)` = clear one file's dirty flag; `pull()` = fast-forward or create a merge-commit +
U-note on divergence. Then write scenario tests: the stuck divergence, the resolver converging in
1 pass and STAYING clean, and the auto-backup racing the resolver + a moving remote.

Keep it in the repo but **gitignored** (`tools/`) so it's available on desktop but never syncs to
the phone. Caveat: a mock models YOUR UNDERSTANDING of isomorphic-git — it can't capture real
async atomicity (overlapping ops, `loadLocalStorage` timing). It gets you to ~75-80% confidence;
the phone confirms the rest.

## Testing a mobile conflict end-to-end (the recipe)

The timing is the hard part — the phone must COMMIT its edit BEFORE it pulls, or git just
fast-forwards and no conflict forms:
1. Desktop: edit a shared line, commit + push (remote now ahead of phone).
2. Phone: **airplane mode ON.** Edit the SAME line differently.
3. Phone: **commit while offline** ("Obsidian Git: Commit all changes") — wait for "committed".
   (This is the make-or-break step — the phone needs its own divergent COMMIT.)
4. Phone: airplane OFF → Pull → real conflict (U flag set).
5. Let the resolver run (or a manual trigger button), then read the verbose log.

A successful outcome: linear history (single-parent commit), no markers, tree clean, and it
STAYS clean (no re-divergence on subsequent passes).

## The obsidian-dashboard skill

For building polished multi-column `dataviewjs` dashboards (the RIGHT technique: inline-styled
HTML built in dataviewjs + Columns plugin, self-injecting `<style>`), there is a separate
`obsidian-dashboard` skill — use it for dashboard layout/widgets. This skill covers the git-sync
+ mobile-JS-correctness side that the dashboard skill doesn't.
