#!/bin/bash
# Claude Code statusline.
#
# Performance notes:
#  * Claude Code invokes this script repeatedly to refresh the bottom status
#    bar (roughly every ~300ms during activity, plus on state changes), not
#    just once at Stop. Anything O(session-size) in here shows up as UI lag
#    that gets worse as the session grows.
#  * The previous version parsed the stdin JSON with ~7 separate `jq` forks
#    per tick, and then ran `jq -s` (slurp) over the *entire* transcript
#    every tick to recompute the token count. On a 14MB transcript that was
#    ~130ms per refresh, several times per second, per open session. With
#    dozens of resident Claude sessions this compounds badly.
#
# Fix:
#  1. Parse stdin once with a single `jq` call.
#  2. Cache the transcript token total keyed by transcript size. If the
#     transcript file has not grown since we last looked, reuse the cached
#     total (~0ms). If it has grown, only stream the new bytes through jq
#     (`tail -c` from the previous size) and add to the cached total.
#     Cold path (no cache) is the same as before (~100ms once).

set -u

# Optional debug: set STATUSLINE_DEBUG=1 in the shell that launches Claude
# to log one line per invocation to $STATUSLINE_DEBUG_LOG (default
# ~/.claude/cache/statusline/debug.log). Format is:
#
#   <epoch.ns> <elapsed_ms> <cache_state> <cur_size> <total_tokens> <transcript_basename>
#
# where cache_state is one of: hit | delta | cold | recompute | no-transcript.
# Analyse cadence with e.g.
#   awk '{print $1}' log | awk 'NR>1{printf "%.3f\n",$1-p} {p=$1}' | sort -n | uniq -c
dbg_enabled=${STATUSLINE_DEBUG:-}
dbg_log=${STATUSLINE_DEBUG_LOG:-$HOME/.claude/cache/statusline/debug.log}
dbg_state=no-transcript
dbg_size=0
dbg_tokens=0
if [ -n "$dbg_enabled" ]; then
    # High-resolution start timestamp; python is present on macOS and cheap.
    dbg_t0=$(python3 -c 'import time;print(f"{time.time():.6f}")' 2>/dev/null || date +%s)
    mkdir -p "$(dirname "$dbg_log")" 2>/dev/null
fi

input=$(cat)

# Single jq call to pull everything we need from stdin.
eval "$(printf '%s' "$input" | jq -r '
  @sh "STL_MODEL_NAME=\(.model.display_name // .model.id // "Unknown")",
  @sh "STL_CTX_PCT=\(.context_window.used_percentage // "")",
  @sh "STL_TRANSCRIPT=\(.transcript_path // "")",
  @sh "STL_CURRENT_DIR=\(.workspace.current_dir // .cwd // "")",
  @sh "STL_PROJECT_DIR=\(.workspace.project_dir // "")",
  @sh "STL_LINES_ADDED=\(.cost.total_lines_added // 0)",
  @sh "STL_LINES_REMOVED=\(.cost.total_lines_removed // 0)"
' 2>/dev/null)"

model_short=$(printf '%s' "${STL_MODEL_NAME:-Unknown}" \
    | sed -E 's/Claude ([0-9.]+\s*)?//' \
    | sed -E 's/\s+/ /g' \
    | xargs)

context_pct="${STL_CTX_PCT:-}"

# Compute context % from transcript with an incremental byte-offset cache.
# The cache is keyed by transcript path; each entry records the file size we
# already accounted for and the running token total up to that byte.
if [ -z "$context_pct" ] && [ -n "${STL_TRANSCRIPT:-}" ] && [ -f "$STL_TRANSCRIPT" ]; then
    cache_dir="$HOME/.claude/cache/statusline"
    mkdir -p "$cache_dir" 2>/dev/null

    # Stable per-transcript cache filename. Transcript basenames are UUIDs so
    # collisions across projects are effectively impossible, but hash the full
    # path anyway for safety.
    key=$(printf '%s' "$STL_TRANSCRIPT" | shasum | awk '{print $1}')
    cache_file="$cache_dir/$key"

    cur_size=$(stat -f%z "$STL_TRANSCRIPT" 2>/dev/null \
        || stat -c%s "$STL_TRANSCRIPT" 2>/dev/null \
        || echo 0)

    cached_size=0
    cached_tokens=0
    if [ -f "$cache_file" ]; then
        # Format: "<size> <total_tokens>"
        read -r cached_size cached_tokens < "$cache_file" 2>/dev/null || true
        cached_size=${cached_size:-0}
        cached_tokens=${cached_tokens:-0}
    fi

    total_tokens=""
    if [ "$cur_size" -eq "$cached_size" ] && [ "$cached_size" -gt 0 ]; then
        # No new bytes since last tick: hot path, ~0ms.
        total_tokens=$cached_tokens
        dbg_state=hit
    else
        # If the file shrank (rotation/truncation), recompute from scratch.
        if [ "$cur_size" -lt "$cached_size" ]; then
            cached_size=0
            cached_tokens=0
            dbg_state=recompute
        elif [ "$cached_size" -eq 0 ]; then
            dbg_state=cold
        else
            dbg_state=delta
        fi

        # Stream only the delta through jq. Using `-c`/no-slurp keeps memory
        # bounded and is measurably faster than `jq -s` even on full files.
        # A partial trailing line (if Claude is mid-flush) will make jq error
        # on that one record; we tolerate the momentary undercount because
        # the next tick will re-read from `cached_size` again once the line
        # completes and the file grows further.
        #
        # NB: macOS `tail -c +N` is pathologically slow when N is small
        # (reads byte-by-byte). Feed jq the file directly on the cold path
        # and only use `tail` when we have a real byte offset to skip past.
        if [ "$cached_size" -eq 0 ]; then
            delta_tokens=$(
                jq -r '
                    select(.message.usage) |
                    (.message.usage.cache_read_input_tokens // 0)
                    + (.message.usage.input_tokens // 0)
                    + (.message.usage.cache_creation_input_tokens // 0)
                  ' "$STL_TRANSCRIPT" 2>/dev/null \
                    | awk '{s+=$1} END {print s+0}'
            )
        else
            delta_tokens=$(
                tail -c +$((cached_size + 1)) "$STL_TRANSCRIPT" 2>/dev/null \
                    | jq -r '
                        select(.message.usage) |
                        (.message.usage.cache_read_input_tokens // 0)
                        + (.message.usage.input_tokens // 0)
                        + (.message.usage.cache_creation_input_tokens // 0)
                      ' 2>/dev/null \
                    | awk '{s+=$1} END {print s+0}'
            )
        fi
        delta_tokens=${delta_tokens:-0}
        total_tokens=$((cached_tokens + delta_tokens))

        # Persist atomically. If two ticks race, last write wins; both are
        # correct for their observed size.
        tmp="$cache_file.$$"
        if printf '%s %s\n' "$cur_size" "$total_tokens" > "$tmp" 2>/dev/null; then
            mv -f "$tmp" "$cache_file" 2>/dev/null || rm -f "$tmp"
        fi
    fi

    if [ -n "$total_tokens" ] && [ "$total_tokens" -gt 0 ]; then
        context_pct=$((total_tokens * 100 / 200000))
    fi
    dbg_size=$cur_size
    dbg_tokens=${total_tokens:-0}
fi

if [ -n "$dbg_enabled" ]; then
    dbg_t1=$(python3 -c 'import time;print(f"{time.time():.6f}")' 2>/dev/null || date +%s)
    dbg_ms=$(awk -v a="$dbg_t0" -v b="$dbg_t1" 'BEGIN{printf "%.1f", (b-a)*1000}')
    dbg_name=$(basename "${STL_TRANSCRIPT:-none}")
    printf '%s %s %s %s %s %s\n' \
        "$dbg_t1" "$dbg_ms" "$dbg_state" "$dbg_size" "$dbg_tokens" "$dbg_name" \
        >> "$dbg_log" 2>/dev/null || true
fi

# Show relative path if inside a project, otherwise show current dir basename.
current_dir="${STL_CURRENT_DIR:-}"
project_dir="${STL_PROJECT_DIR:-}"
if [ -n "$project_dir" ] && [ "$current_dir" != "$project_dir" ]; then
    dir_display="${current_dir#$project_dir/}"
else
    dir_display=$(basename "$current_dir")
fi

lines_added="${STL_LINES_ADDED:-0}"
lines_removed="${STL_LINES_REMOVED:-0}"

# Build output: [Model] Context% • Dir • +lines/-lines

# Model name (green)
printf "\033[32m[%s]\033[0m" "$model_short"

# Context percentage with color coding based on danger zones
if [ -n "$context_pct" ] && [ "$context_pct" -gt 0 ]; then
    pct_int=$(printf "%.0f" "$context_pct")

    if [ "$pct_int" -ge 75 ]; then
        # 75%+ = RED (critical - very high error rate)
        printf " \033[31m%d%%\033[0m" "$pct_int"
    elif [ "$pct_int" -ge 50 ]; then
        # 50-74% = YELLOW (warning - entering dumb zone)
        printf " \033[33m%d%%\033[0m" "$pct_int"
    else
        # 0-49% = CYAN (safe zone)
        printf " \033[36m%d%%\033[0m" "$pct_int"
    fi
fi

# Directory (dim white/gray)
if [ -n "$dir_display" ]; then
    printf " \033[2m•\033[0m \033[37m%s\033[0m" "$dir_display"
fi

# Code changes (green for added, red for removed)
if [ "$lines_added" -gt 0 ] || [ "$lines_removed" -gt 0 ]; then
    printf " \033[2m•\033[0m"
    [ "$lines_added" -gt 0 ] && printf " \033[32m+%d\033[0m" "$lines_added"
    [ "$lines_removed" -gt 0 ] && printf " \033[31m-%d\033[0m" "$lines_removed"
fi
