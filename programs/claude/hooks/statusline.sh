#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Extract model display name
model_name=$(echo "$input" | jq -r '.model.display_name // .model.id // "Unknown"')

# Simplify model name
model_short=$(echo "$model_name" | sed -E 's/Claude ([0-9.]+\s*)?//' | sed -E 's/\s+/ /g' | xargs)

# Try to get context_window from JSON first (newer Claude Code versions)
context_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# If context_window not available, calculate from transcript
if [ -z "$context_pct" ]; then
    transcript_path=$(echo "$input" | jq -r '.transcript_path // ""')

    if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
        # Sum up all input tokens from the transcript
        total_tokens=$(jq -s '[.[].message.usage | select(. != null) | (.cache_read_input_tokens // 0) + (.input_tokens // 0) + (.cache_creation_input_tokens // 0)] | add' "$transcript_path" 2>/dev/null)

        if [ -n "$total_tokens" ] && [ "$total_tokens" -gt 0 ]; then
            # Calculate percentage (200k context window)
            context_pct=$((total_tokens * 100 / 200000))
        fi
    fi
fi

# Build output with color (green for model name, cyan for percentage)
if [ -n "$context_pct" ] && [ "$context_pct" -gt 0 ]; then
    printf "\033[32m[%s]\033[0m \033[36m%d%%\033[0m" "$model_short" "$context_pct"
else
    printf "\033[32m[%s]\033[0m" "$model_short"
fi
