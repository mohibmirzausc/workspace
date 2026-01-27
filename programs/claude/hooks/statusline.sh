#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Extract model display name
model_name=$(echo "$input" | jq -r '.model.display_name // .model.id // "Unknown"')
model_short=$(echo "$model_name" | sed -E 's/Claude ([0-9.]+\s*)?//' | sed -E 's/\s+/ /g' | xargs)

# Get context percentage
context_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# If context_window not available, calculate from transcript
if [ -z "$context_pct" ]; then
    transcript_path=$(echo "$input" | jq -r '.transcript_path // ""')
    if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
        total_tokens=$(jq -s '[.[].message.usage | select(. != null) | (.cache_read_input_tokens // 0) + (.input_tokens // 0) + (.cache_creation_input_tokens // 0)] | add' "$transcript_path" 2>/dev/null)
        if [ -n "$total_tokens" ] && [ "$total_tokens" -gt 0 ]; then
            context_pct=$((total_tokens * 100 / 200000))
        fi
    fi
fi

# Extract directory info
current_dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // ""')

# Show relative path if in project, otherwise show current dir basename
if [ -n "$project_dir" ] && [ "$current_dir" != "$project_dir" ]; then
    rel_dir="${current_dir#$project_dir/}"
    dir_display="$rel_dir"
else
    dir_display=$(basename "$current_dir")
fi

# Extract code changes
lines_added=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
lines_removed=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')

# Build output with colors
# Format: [Model] Context% • Dir • +lines/-lines

# Model name (green)
printf "\033[32m[%s]\033[0m" "$model_short"

# Context percentage with color coding based on danger zones
if [ -n "$context_pct" ] && [ "$context_pct" -gt 0 ]; then
    # Round to integer for comparison
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
