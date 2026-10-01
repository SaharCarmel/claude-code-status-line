#!/bin/bash

# Claude Code Status Line
# Displays project info, git status, model, context usage, and usage limits

# Read JSON input from stdin
input=$(cat)
current_dir=$(echo "$input" | jq -r '.workspace.current_dir')
session_id=$(echo "$input" | jq -r '.session_id // "unknown"')
model=$(echo "$input" | jq -r '.model.display_name')

current_time=$(date +%s)

# Get current conversation hash to detect changes for shortcuts detection
project_sessions_dir="$HOME/.claude/projects/$(echo "$current_dir" | sed 's|/|-|g')"
current_session_file="$project_sessions_dir/${session_id}.jsonl"
current_conversation_hash=""

if [[ -f "$current_session_file" ]]; then
    # Create hash of recent conversation (last 10 entries)
    current_conversation_hash=$(tail -10 "$current_session_file" | shasum -a 256 | cut -d' ' -f1)
fi


# Code quality shortcuts detection with caching
shortcuts_cache_file="$HOME/.claude/shortcuts_cache_${session_id}"
shortcuts_timestamp_file="$HOME/.claude/shortcuts_timestamp_${session_id}"
shortcuts_hash_file="$HOME/.claude/shortcuts_hash_${session_id}"
shortcuts_cache_duration=300  # Check every 5 minutes

shortcuts_indicator=""
refresh_shortcuts=false

# Check if shortcuts cache needs refresh
if [[ ! -f "$shortcuts_timestamp_file" ]] || [[ ! -f "$shortcuts_cache_file" ]] || [[ ! -f "$shortcuts_hash_file" ]]; then
    refresh_shortcuts=true
else
    last_shortcuts_update=$(cat "$shortcuts_timestamp_file" 2>/dev/null || echo "0")
    last_shortcuts_hash=$(cat "$shortcuts_hash_file" 2>/dev/null || echo "")

    # Refresh if conversation changed OR if it's been too long since last check
    if [[ "$current_conversation_hash" != "$last_shortcuts_hash" ]] || (( current_time - last_shortcuts_update > shortcuts_cache_duration )); then
        refresh_shortcuts=true
    fi
fi

if [[ "$refresh_shortcuts" == "true" ]]; then
    # Change to dedicated directory to avoid polluting project history
    summary_dir="$HOME/.claude/statusline-summaries"
    if cd "$summary_dir" 2>/dev/null; then
        # Get Claude's recent conversation context
        shortcuts_context=""
        project_sessions_dir="$HOME/.claude/projects/$(echo "$current_dir" | sed 's|/|-|g')"

        if [[ -d "$project_sessions_dir" ]]; then
            # Get the specific session file for this instance
            current_session="$project_sessions_dir/${session_id}.jsonl"

            if [[ -f "$current_session" ]]; then
                # Get all messages, find last user input, then get everything after it
                all_messages=$(jq -r '
                    select(.type == "user" or (.type == "assistant" and .message.content != null)) |
                    if .type == "user" then
                        "USER: " + (.message.content | if type == "string" then . else .[0].text // "..." end)
                    elif .type == "assistant" then
                        "CLAUDE: " + (.message.content[] | select(.type == "text") | .text)
                    else
                        empty
                    end
                ' "$current_session" 2>/dev/null)

                # Find the last user input and get everything from there
                if [[ -n "$all_messages" ]]; then
                    # Get line number of last USER: message
                    last_user_line=$(echo "$all_messages" | grep -n "^USER:" | tail -1 | cut -d: -f1)

                    if [[ -n "$last_user_line" ]]; then
                        # Get all messages from last user input onwards
                        session_data=$(echo "$all_messages" | tail -n +"$last_user_line" | head -c 800)
                        shortcuts_context="Current session since last user input: $session_data"
                    fi
                fi
            fi
        fi

        # Create shortcuts detection prompt
        if [[ -n "$shortcuts_context" ]]; then
            shortcuts_prompt="<conversation_context>
$shortcuts_context
</conversation_context>

<task>
You are a code quality detector. Analyze the conversation for signs that Claude is taking shortcuts or avoiding proper implementations.

Look for these patterns in Claude's responses:
- Using mock data instead of real implementations
- Suggesting placeholder/stub code
- Avoiding complex logic with \"TODO\" or \"simplified\" comments
- Using hardcoded values instead of proper configuration
- Skipping error handling or validation
- Suggesting \"quick fixes\" instead of proper solutions
- Avoiding database/API integrations with fake data

CRITICAL: Output ONLY one indicator from this exact list. No explanations, no extra text:

🚨 MOCK
⚡ SHORTCUT
🎯 SOLID
❓ UNKNOWN

Choose the most appropriate indicator based on the conversation. Output the EXACT text above, nothing more.
</task>"

            shortcuts_output=$(echo "$shortcuts_prompt" | claude --model haiku -p 2>/dev/null)
            if [[ $? -eq 0 && -n "$shortcuts_output" ]]; then
                # Extract just the valid indicators, ignore any extra text
                shortcuts_indicator=""
                if echo "$shortcuts_output" | grep -q "🚨 MOCK"; then
                    shortcuts_indicator="MOCK"
                elif echo "$shortcuts_output" | grep -q "⚡ SHORTCUT"; then
                    shortcuts_indicator="SHORTCUT"
                elif echo "$shortcuts_output" | grep -q "🎯 SOLID"; then
                    shortcuts_indicator="SOLID"
                elif echo "$shortcuts_output" | grep -q "❓ UNKNOWN"; then
                    shortcuts_indicator="UNKNOWN"
                fi

                if [[ -n "$shortcuts_indicator" ]]; then
                    echo "$shortcuts_indicator" > "$shortcuts_cache_file"
                    echo "$current_time" > "$shortcuts_timestamp_file"
                    echo "$current_conversation_hash" > "$shortcuts_hash_file"
                fi
            fi
        fi
    fi
fi

# Read cached shortcuts indicator
if [[ -f "$shortcuts_cache_file" ]]; then
    shortcuts_indicator=$(cat "$shortcuts_cache_file" 2>/dev/null)
fi

# Get git information
git_info=""
if cd "$current_dir" 2>/dev/null; then
    if git_branch=$(git branch --show-current 2>/dev/null); then
        if [[ -n "$git_branch" ]]; then
            if git status --porcelain 2>/dev/null | grep -q .; then
                git_info=" git:($git_branch) ✗"
            else
                git_info=" git:($git_branch)"
            fi
        fi
    fi
fi

# Session PRs: every PR Claude Code linked to this session (its own "pr-link"
# transcript records, which include PRs opened by subagents and workflows), plus
# the current branch's PR. Statuses are fetched in the background with one
# GraphQL call and cached, so the status line never waits on the network.
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')
[[ -z "$transcript_path" ]] && transcript_path="$current_session_file"

pr_cache_file="$HOME/.claude/session_prs_${session_id}"
pr_timestamp_file="${pr_cache_file}_ts"
pr_lock_dir="${pr_cache_file}_lock"
pr_cache_duration=60
pr_max_shown=5

# Collect the session's PRs and write one TSV line per PR to the cache:
# number, state, isDraft, reviewDecision, ciState, headRefName, url
refresh_session_prs() {
    local links repo_slug query aliases slug n i=0
    links=$(grep -h '"type":"pr-link"' "$transcript_path" 2>/dev/null \
        | jq -r 'select(.prRepository and .prNumber) | "\(.prRepository)\t\(.prNumber)"' 2>/dev/null | sort -u)

    local fields='number state isDraft reviewDecision headRefName url commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }'
    query=""
    # Linked PRs, grouped per repository
    for slug in $(echo "$links" | cut -f1 | grep -v '^$' | sort -u); do
        aliases=""
        for n in $(echo "$links" | awk -F'\t' -v s="$slug" '$1 == s { print $2 }'); do
            aliases+=" p${n}: pullRequest(number: ${n}) { ${fields} }"
        done
        query+=" r$((i++)): repository(owner: \"${slug%%/*}\", name: \"${slug##*/}\") {${aliases} }"
    done
    # The current branch's PR, in the current repository
    repo_slug=$(cd "$current_dir" 2>/dev/null && git remote get-url origin 2>/dev/null \
        | sed -nE 's#^.*github\.com[:/]([^/]+/[^/]+)$#\1#p' | sed 's/\.git$//')
    if [[ -n "$repo_slug" && -n "$git_branch" && "$git_branch" != "main" && "$git_branch" != "master" ]]; then
        query+=" r$((i++)): repository(owner: \"${repo_slug%%/*}\", name: \"${repo_slug##*/}\") { b: pullRequests(headRefName: \"${git_branch//\"/}\", first: 1, orderBy: {field: CREATED_AT, direction: DESC}, states: [OPEN, MERGED, CLOSED]) { nodes { ${fields} } } }"
    fi

    local result=""
    if [[ -n "$query" ]]; then
        result=$(gh api graphql -f query="query {${query} }" 2>/dev/null) || return 1
    fi
    echo "$result" | jq -r '
        [.data // {} | .[] | .[]? | if type == "object" and has("nodes") then .nodes[] else . end
         | select(type == "object" and .number != null)]
        | unique_by(.url)[]
        | [.number, .state, .isDraft, (.reviewDecision // ""),
           (.commits.nodes[0].commit.statusCheckRollup.state // ""), .headRefName, .url]
        | @tsv' > "${pr_cache_file}.tmp" 2>/dev/null && mv "${pr_cache_file}.tmp" "$pr_cache_file"
    # Claude Code's own footer badge shows the first PR linked to the session;
    # remember it so the list below does not show that PR a second time.
    grep -h -m1 '"type":"pr-link"' "$transcript_path" 2>/dev/null | jq -r '.prUrl // empty' > "${pr_cache_file}_badge" 2>/dev/null
    date +%s > "$pr_timestamp_file"
}

last_pr_update=$(cat "$pr_timestamp_file" 2>/dev/null || echo 0)
if (( current_time - last_pr_update > pr_cache_duration )) && mkdir "$pr_lock_dir" 2>/dev/null; then
    ( refresh_session_prs; rmdir "$pr_lock_dir" ) </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null
elif [[ -d "$pr_lock_dir" ]] && [[ -n $(find "$pr_lock_dir" -maxdepth 0 -mmin +2 2>/dev/null) ]]; then
    rmdir "$pr_lock_dir" 2>/dev/null  # stale lock from a killed refresh
fi

# Render: open PRs first, then drafts, merged, closed. Current branch in bold.
pr_display=""
if [[ -s "$pr_cache_file" ]]; then
    badge_url=$(cat "${pr_cache_file}_badge" 2>/dev/null)
    pr_items=()
    pr_count=0
    while IFS=$'\t' read -r num state draft review ci head url; do
        [[ -z "$num" || "$url" == "$badge_url" ]] && continue
        pr_count=$((pr_count + 1))
        (( pr_count > pr_max_shown )) && continue
        if [[ "$state" == "MERGED" ]]; then
            color="\033[35m"; mark="⇲"
        elif [[ "$state" == "CLOSED" ]]; then
            color="\033[2m"; mark="⊘"
        elif [[ "$draft" == "true" ]]; then
            color="\033[2m"; mark="◐"
        else
            case "$ci" in
                SUCCESS) color="\033[32m"; mark="✓" ;;
                FAILURE|ERROR) color="\033[31m"; mark="✗" ;;
                PENDING|EXPECTED) color="\033[33m"; mark="⏳" ;;
                *) color=""; mark="" ;;
            esac
        fi
        [[ "$head" == "$git_branch" ]] && color="${color}\033[1m"
        flag=""
        [[ "$state" == "OPEN" && "$review" == "CHANGES_REQUESTED" ]] && flag="\033[31m!"
        pr_items+=("\033]8;;${url}\a${color}#${num}${mark}${flag}\033[0m\033]8;;\a")
    done < <(awk -F'\t' '{
            rank = ($2 == "MERGED") ? 2 : ($2 == "CLOSED") ? 3 : ($3 == "true") ? 1 : 0
            print rank "\t" $0
        }' "$pr_cache_file" | sort -t$'\t' -k1,1n -k2,2nr | cut -f2-)

    if (( pr_count > 0 )); then
        label="PRs"; (( pr_count == 1 )) && label="PR"
        pr_display=" | ${label} ${pr_items[*]}"
        (( pr_count > pr_max_shown )) && pr_display+=" \033[2m+$((pr_count - pr_max_shown))\033[0m"
    fi
fi

# Session Linear tickets: inferred from the transcript (branch names, tickets the
# session wrote to, created or read, identifiers the user typed) and from the
# tickets Linear links to the session's PRs. linear-session-tickets.py does the
# scoring, rolls sibling tickets up to their parent, and fetches statuses; it
# runs in the background and is cached like the PRs. Each ticket is a link that
# opens the Linear desktop app.
script_dir=$(dirname "$(readlink "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")
linear_cache_file="$HOME/.claude/session_linear_${session_id}"
linear_timestamp_file="${linear_cache_file}_ts"
linear_lock_dir="${linear_cache_file}_lock"
linear_cache_duration=120
linear_max_shown=3

last_linear_update=$(cat "$linear_timestamp_file" 2>/dev/null || echo 0)
if [[ -f "$transcript_path" && -f "$script_dir/linear-session-tickets.py" ]] \
    && (( current_time - last_linear_update > linear_cache_duration )) && mkdir "$linear_lock_dir" 2>/dev/null; then
    (
        pr_args=()
        while read -r url; do pr_args+=(--pr "$url"); done < <(
            { cut -f7 "$pr_cache_file"; cat "${pr_cache_file}_badge"; } 2>/dev/null | grep '^https://' | sort -u)
        /usr/bin/python3 "$script_dir/linear-session-tickets.py" "$transcript_path" "$linear_cache_file" \
            --branch "$git_branch" "${pr_args[@]}"
        date +%s > "$linear_timestamp_file"
        rmdir "$linear_lock_dir"
    ) </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null
elif [[ -d "$linear_lock_dir" ]] && [[ -n $(find "$linear_lock_dir" -maxdepth 0 -mmin +2 2>/dev/null) ]]; then
    rmdir "$linear_lock_dir" 2>/dev/null  # stale lock from a killed refresh
fi

# Render: main ticket first; a rolled-up parent shows how many of its children
# the session touched. The status is drawn in Linear's own colour for it.
linear_display=""
if [[ -s "$linear_cache_file" ]]; then
    linear_items=""
    linear_count=0
    while IFS=$'\t' read -r ident state rgb url children title; do
        [[ -z "$ident" ]] && continue
        linear_count=$((linear_count + 1))
        (( linear_count > linear_max_shown )) && continue
        state_color=""
        [[ -n "$rgb" ]] && state_color="\033[38;2;${rgb}m"
        rollup=""
        (( children > 0 )) && rollup=" \033[2m×${children}\033[0m"
        [[ -n "$linear_items" ]] && linear_items+=" \033[2m·\033[0m "
        linear_items+="\033]8;;${url}\a${ident} ${state_color}${state}\033[0m${rollup}\033]8;;\a"
    done < "$linear_cache_file"
    if (( linear_count > 0 )); then
        linear_display=" | ${linear_items}"
        (( linear_count > linear_max_shown )) && linear_display+=" \033[2m+$((linear_count - linear_max_shown))\033[0m"
    fi
fi

# Project name
basename=$(basename "$current_dir")

# Get context window usage from Claude Code's statusline JSON (context_window.*)
context_max=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
context_used=$(echo "$input" | jq -r '.context_window.current_usage | if . == null then 0 else (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0) end')
[[ "$context_used" =~ ^[0-9]+$ ]] || context_used=0

# Window size fallback: 1M for [1m] models, otherwise 200k
if ! [[ "$context_max" =~ ^[0-9]+$ ]] || [[ "$context_max" -eq 0 ]]; then
    model_id=$(echo "$input" | jq -r '.model.id // ""')
    if [[ "$model_id" == *"[1m]"* || "$model" == *"1M"* ]]; then
        context_max=1000000
    else
        context_max=200000
    fi
fi

# Fallback: if JSON doesn't have usage yet, read the last usage from the session file
if [[ "$context_used" -eq 0 ]] && [[ -f "$current_session_file" ]]; then
    total_tokens=$(tail -50 "$current_session_file" | grep '"usage"' | tail -1 | \
        jq '.message.usage | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)' 2>/dev/null)
    if [[ -n "$total_tokens" && "$total_tokens" != "null" && "$total_tokens" -gt 0 ]]; then
        context_used=$total_tokens
    fi
fi

# Calculate percentage
if [[ "$context_max" -gt 0 ]] && [[ "$context_used" -gt 0 ]]; then
    context_percentage=$((context_used * 100 / context_max))
else
    context_percentage=0
fi

# Generate progress bar (10 characters wide)
bar_width=10
if [[ "$context_percentage" -gt 0 ]]; then
    filled=$((context_percentage * bar_width / 100))
    [[ "$filled" -lt 1 ]] && filled=1  # Show at least 1 block if there's any usage
else
    filled=0
fi
empty=$((bar_width - filled))

# Choose color based on percentage
if [[ "$context_percentage" -lt 50 ]]; then
    bar_color="\033[32m"  # Green
elif [[ "$context_percentage" -lt 75 ]]; then
    bar_color="\033[33m"  # Yellow
elif [[ "$context_percentage" -lt 90 ]]; then
    bar_color="\033[38;5;208m"  # Orange
else
    bar_color="\033[31m"  # Red
fi

# Build progress bar with filled and empty segments
progress_bar=""
for ((i=0; i<filled; i++)); do
    progress_bar+="█"
done
for ((i=0; i<empty; i++)); do
    progress_bar+="░"
done

# Format token count (e.g., 15k or 150k)
if [[ "$context_used" -ge 1000000 ]]; then
    formatted_tokens="$(printf "%.1f" "$(echo "$context_used / 1000000" | bc -l)")M"
elif [[ "$context_used" -ge 1000 ]]; then
    formatted_tokens="$((context_used / 1000))k"
elif [[ "$context_used" -gt 0 ]]; then
    formatted_tokens="$context_used"
else
    formatted_tokens="--"
fi

# Build context info with progress bar
if [[ "$context_used" -gt 0 ]]; then
    context_info="${bar_color}${progress_bar}\033[0m ${formatted_tokens} (${context_percentage}%)"
else
    context_info="${bar_color}${progress_bar}\033[0m -- (--)"
fi

# Usage limits (5-hour session + weekly) from statusline JSON (Pro/Max only)
limit_color() {
    local pct=$1
    if (( pct < 50 )); then
        echo "\033[32m"   # Green
    elif (( pct < 75 )); then
        echo "\033[33m"   # Yellow
    elif (( pct < 90 )); then
        echo "\033[38;5;208m"  # Orange
    else
        echo "\033[31m"   # Red
    fi
}

# Build a small colored progress bar: mini_bar <pct> <width>
mini_bar() {
    local pct=$1 width=$2
    local fill=$(((pct * width + 50) / 100))
    (( pct > 0 && fill < 1 )) && fill=1
    (( fill > width )) && fill=$width
    local bar=""
    for ((i=0; i<fill; i++)); do bar+="█"; done
    for ((i=fill; i<width; i++)); do bar+="░"; done
    echo "$(limit_color "$pct")${bar}\033[0m"
}

limits_display=""
five_hour_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_day_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
five_hour_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_day_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty' | cut -d. -f1)

if [[ -n "$five_hour_pct" ]]; then
    five_hour_int=$(printf "%.0f" "$five_hour_pct")
    reset_str=""
    if [[ -n "$five_hour_reset" ]]; then
        reset_time=$(date -r "$five_hour_reset" +%H:%M 2>/dev/null)
        [[ -n "$reset_time" ]] && reset_str=" \033[2m↻ ${reset_time}\033[0m"
    fi
    limits_display="5h $(mini_bar "$five_hour_int" 5) ${five_hour_int}%${reset_str}"
fi

if [[ -n "$seven_day_pct" ]]; then
    seven_day_int=$(printf "%.0f" "$seven_day_pct")
    [[ -n "$limits_display" ]] && limits_display="${limits_display} | "
    limits_display="${limits_display}wk $(mini_bar "$seven_day_int" 5) ${seven_day_int}%"
    # Time until the weekly reset: whole days, or hours on the last day
    if [[ "$seven_day_reset" =~ ^[0-9]+$ ]] && (( seven_day_reset > current_time )); then
        secs_left=$((seven_day_reset - current_time))
        if (( secs_left >= 86400 )); then
            left_str="$((secs_left / 86400))d"
        else
            left_str="$(((secs_left + 3599) / 3600))h"
        fi
        reset_when=$(date -r "$seven_day_reset" "+%a %H:%M" 2>/dev/null)
        limits_display="${limits_display} \033[2m↻ ${left_str}${reset_when:+ · $reset_when}\033[0m"
    fi
fi

# Shorten model name (strip "Claude " prefix)
short_model=$(echo "$model" | sed 's/^Claude //')

# Build the complete status line
status_line="\033[1;32m➜\033[0m \033[36m${basename}\033[0m${git_info}${pr_display}${linear_display}"
status_line="${status_line} | \033[33m${short_model}\033[0m"
status_line="${status_line} | ${context_info}"

# Add usage limits if available
if [[ -n "$limits_display" ]]; then
    status_line="${status_line} | ${limits_display}"
fi

# Add shortcuts indicator if available
if [[ -n "$shortcuts_indicator" ]]; then
    status_line="${status_line} | \033[33m${shortcuts_indicator}\033[0m"
fi

echo -e "$status_line"
