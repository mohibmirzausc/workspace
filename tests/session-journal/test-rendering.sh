#!/usr/bin/env bash
# Entry readability: dedupe, title summarization, and markdown rendering.
#
# All three were real defects observed in a live journal: 31 copies of one body,
# titles that were 120-char slices of markdown tables, and bodies showing literal
# "##" and "**" because the page never rendered markdown.
set -uo pipefail
. "$(dirname "$0")/assert.sh"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$ROOT/programs/claude/hooks/lib/session-journal-common.sh"
TPL="$ROOT/programs/claude/hooks/lib/journal-template.html"

setup_sandbox
trap teardown_sandbox EXIT
. "$LIB"
echo ENABLED >"$SJ_STATE_FILE"
sj_init >/dev/null
d=$(sj_dir)

# --- Dedupe ------------------------------------------------------------------
# Compaction re-fires SessionStart/SubagentStop, which replayed an identical 2KB
# report minutes apart (observed either side of a `Session compact` entry).
before=$(wc -l <"$d/entries.txt")
sj_append progress agent "replayed" "identical body"
sj_append progress agent "replayed" "identical body"
sj_append progress agent "replayed" "identical body"
assert_eq "$(($(wc -l <"$d/entries.txt") - before))" "1" "identical appends collapse to one"

# A differing body is a different event, even under the same title.
sj_append progress agent "replayed" "a DIFFERENT body"
assert_eq "$(($(wc -l <"$d/entries.txt") - before))" "2" "differing body still appends"

# Dedupe must be bounded, not global: a repeat separated by more than the window
# is real recurrence. This also pins the cost of the check as journals grow.
for i in $(seq 1 "$((SJ_DEDUPE_WINDOW + 2))"); do sj_append progress agent "filler $i" "b$i"; done
n=$(wc -l <"$d/entries.txt")
sj_append progress agent "replayed" "identical body"
assert_eq "$(($(wc -l <"$d/entries.txt") - n))" "1" "repeat beyond the window is recorded"

# The signature must actually be persisted, or every future dedupe silently
# no-ops. (An early draft computed `sig` AFTER the jq call that serialized it,
# so every entry carried "" and matched every other empty-sig entry.)
sig=$(tail -1 "$d/entries.txt" | jq -r '.sig')
assert_eq "${#sig}" "16" "sig persisted on the entry"

# Distinct content must not share a signature.
s1=$(printf '%s' "$(sj_append progress agent "sig-a" "body-a"; tail -1 "$d/entries.txt" | jq -r .sig)")
s2=$(printf '%s' "$(sj_append progress agent "sig-b" "body-b"; tail -1 "$d/entries.txt" | jq -r .sig)")
[ "$s1" != "$s2" ] || fail "distinct entries collided on sig"

# --- Title summarization -----------------------------------------------------
# The observed bad title, verbatim:
#   "## Token cost of journaling **Per session, unconditional: ~284 tokens** | Cost |"
t=$(printf '## Token cost of journaling\n\n**Per session: ~284 tokens**\n\n| Cost | Tokens |\n|---|---|\n' |
  sj_summarize_line 120)
assert_eq "$t" "Token cost of journaling" "heading text becomes the title"
case "$t" in *'#'* | *'**'* | *'|'*) fail "markdown syntax leaked into title: [$t]" ;; esac

# A body that opens with a table must not yield a row of pipes as its title.
t=$(printf '| Cost | Tokens |\n|---|---|\n| a | 1 |\n\nThe real prose starts here.\n' | sj_summarize_line 120)
assert_eq "$t" "The real prose starts here." "table rows are skipped"

# Code fences must never supply a title.
t=$(printf '```bash\nrm -rf /\n```\nActual summary sentence.\n' | sj_summarize_line 120)
assert_eq "$t" "Actual summary sentence." "fenced code is skipped"

# Bullets keep their text, lose their marker.
t=$(printf -- '- Fixed the lock steal. More detail after.\n' | sj_summarize_line 120)
assert_eq "$t" "Fixed the lock steal." "cuts at the sentence boundary"

# With no sentence boundary in range, cut on a word boundary — never mid-word.
t=$(printf 'aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj kkkk llll mmmm\n' | sj_summarize_line 30)
[ "${#t}" -le 31 ] || fail "title exceeded max: [$t]"
case "$t" in *…) ;; *) fail "truncated title lacks an ellipsis: [$t]" ;; esac
case "$t" in *' ') fail "title ends in whitespace" ;; esac

# Degenerate input must not hang or emit junk.
assert_eq "$(printf '' | sj_summarize_line 120)" "" "empty input yields empty"
assert_eq "$(printf '\n\n   \n' | sj_summarize_line 120)" "" "whitespace-only yields empty"
t=$(printf '```\nunterminated fence\n' | sj_summarize_line 120)
assert_eq "$t" "" "unterminated fence consumes to EOF without hanging"

# --- Markdown rendering in the page ------------------------------------------
assert_file_exists "$d/index.html"

# Bodies must go through the renderer; titles must NOT (they are plain text).
grep -q "md(e.body)" "$d/index.html" || fail "body is not markdown-rendered"
grep -q 'class="t">' "$d/index.html" || fail "title element missing"
grep -qE "class=\"t\">' \+ esc\(e\.title\)" "$d/index.html" ||
  fail "title must stay escaped-only, not markdown-rendered"

# XSS: the renderer escapes FIRST, then inserts its own tags. If that order is
# ever inverted, an agent-written body containing HTML becomes executable.
esc_line=$(grep -n 'var lines = esc(' "$d/index.html" | head -1 | cut -d: -f1)
[ -n "$esc_line" ] || fail "md() does not escape its input up front"

# pre-wrap on .b would preserve source newlines between rendered blocks as gaps.
grep -qE '^\s*\.b\{[^}]*white-space:pre-wrap' "$d/index.html" &&
  fail "white-space:pre-wrap still set on .b; rendered blocks will show stray gaps"

# Styles must exist for every element the renderer can emit, or output is unstyled.
for sel in '.b table' '.b th,.b td' '.b pre' '.b code' '.b ul,.b ol' '.b blockquote' '.b .mdh' '.b strong'; do
  grep -qF "$sel" "$d/index.html" || fail "no style rule for $sel"
done

# javascript:/data: URLs must not survive as hrefs. The link regex allowlists
# http(s) and relative paths, so anything else is left as literal text.
#
# Assert on the CONSTRUCTION, not on prose: the template legitimately mentions
# "javascript:" in the comment explaining this very defence, and an earlier
# version of this test failed on that comment.
grep -qF 'https?:\/\/[^\s)]+|\.{0,2}\/[^\s)]*' "$d/index.html" ||
  fail "link href allowlist pattern missing or changed"

# Exercise the renderer for real rather than inferring behaviour from greps.
if command -v node >/dev/null 2>&1; then
  harness="$SANDBOX/render-harness.js"
  # Extract just esc() and md() by brace-matching from each declaration, rather
  # than filtering DOM lines out of the whole IIFE — line filtering left dangling
  # braces and the harness failed to parse.
  {
    awk '/^<script>$/{s=1;next} /^<\/script>$/{s=0}
         s && /^  function (esc|md)\(/ {emit=1; depth=0}
         emit {
           n = gsub(/\{/, "{"); depth += n
           n = gsub(/\}/, "}"); depth -= n
           print
           if (depth <= 0) emit = 0
         }' "$d/index.html"
    cat <<'JS'
var fails = 0;
function chk(cond, msg) { if (!cond) { console.log('RENDER-FAIL: ' + msg); fails++; } }

var h = md('## Heading\n\n**bold** and *ital* and `code`\n');
chk(h.indexOf('<strong>bold</strong>') > -1, 'bold not rendered');
chk(h.indexOf('<em>ital</em>') > -1, 'italic not rendered');
chk(h.indexOf('<code>code</code>') > -1, 'code span not rendered');
chk(h.indexOf('##') === -1, 'literal ## survived');
chk(h.indexOf('**') === -1, 'literal ** survived');

var t = md('| Cost | Tokens |\n|---|---|\n| Skill | 68 |\n');
chk(t.indexOf('<table>') > -1 && t.indexOf('<th>Cost</th>') > -1, 'table not rendered');
chk(t.indexOf('<td>Skill</td>') > -1, 'table cell missing');
chk(t.indexOf('|') === -1, 'literal pipes survived');

var l = md('- one\n- two\n');
chk(l.indexOf('<ul><li>one</li><li>two</li></ul>') > -1, 'bullet list not rendered');
chk(md('1. a\n2. b\n').indexOf('<ol>') > -1, 'ordered list not rendered');

var f = md('```\nrm -rf /\n```\n');
chk(f.indexOf('<pre><code>rm -rf /</code></pre>') > -1, 'fenced code not rendered');
chk(md('> quoted\n').indexOf('<blockquote>') > -1, 'blockquote not rendered');
chk(md('---\n').indexOf('<hr>') > -1, 'hr not rendered');

// Markup inside a code span must stay literal, not be re-processed.
chk(md('`**not bold**`').indexOf('<strong>') === -1, 'markup inside code span was processed');

// XSS: agent-written text is escaped BEFORE any tag is inserted.
var x = md('<img src=x onerror=alert(1)>\n');
chk(x.indexOf('<img') === -1, 'raw <img> survived — XSS');
chk(x.indexOf('&lt;img') > -1, 'html not escaped');
var q = md('normal "quotes" and \'apostrophes\'');
chk(q.indexOf('&quot;') > -1 && q.indexOf('&#39;') > -1, 'quotes not escaped');

// Only safe URL schemes become live links.
chk(md('[x](https://a.test/p)').indexOf('href="https://a.test/p"') > -1, 'https link not rendered');
chk(md('[x](./rel/path)').indexOf('href="./rel/path"') > -1, 'relative link not rendered');
chk(md('[x](javascript:alert(1))').indexOf('href="javascript') === -1, 'javascript: URL became an href');
chk(md('[x](data:text/html,hi)').indexOf('href="data:') === -1, 'data: URL became an href');

// Degenerate input must not throw or hang.
['', null, undefined, '\n\n\n', '```\nunterminated\n', '|||', '#', '- '].forEach(function (s) {
  try { md(s); } catch (e) { console.log('RENDER-FAIL: threw on ' + JSON.stringify(s) + ': ' + e.message); fails++; }
});

// A plain body must not be mangled, and newlines within a paragraph survive.
chk(md('just prose').indexOf('<p>just prose</p>') > -1, 'plain prose mangled');
chk(md('line one\nline two').indexOf('line one\nline two') > -1, 'intra-paragraph newline lost');

console.log(fails === 0 ? 'RENDER-OK' : 'RENDER-FAILURES=' + fails);
JS
  } >"$harness"
  out=$(node "$harness" 2>&1) || fail "renderer harness crashed: $out"
  printf '%s\n' "$out" | grep -q 'RENDER-OK' || fail "markdown renderer defects:
$out"
fi

# The page must remain self-contained: no CDN, no build step.
grep -qE '<script[^>]+src=|<link[^>]+href="https?:' "$d/index.html" &&
  fail "page pulls a remote asset; it must render offline"

# Still no EventSource: subscribing to the gallery's SSE would hard-reload the
# page on every append. Match a CONSTRUCTION, not the comment explaining why.
grep -qE '(new[[:space:]]+EventSource|=[[:space:]]*EventSource)' "$d/index.html" &&
  fail "EventSource constructed; appends will trigger reload storms"

# Node must be able to parse the inline script — a syntax error would leave the
# page permanently blank, which no shell-level grep can detect.
if command -v node >/dev/null 2>&1; then
  # node infers module format from the extension and refuses a suffixless temp
  # file, so give it a .js name.
  script="$SANDBOX/inline-check.js"
  awk '/^<script>$/{f=1;next} /^<\/script>$/{f=0} f' "$d/index.html" >"$script"
  [ -s "$script" ] || fail "could not extract the inline script"
  node --check "$script" 2>&1 || fail "inline script has a syntax error"
fi

echo "test-rendering passed"
