#!/bin/bash

# Claude Code Status Line
# Displays project info, git status, model, costs, and code quality indicators

# Read JSON input from stdin
input=$(cat)
current_dir=$(echo "$input" | jq -r '.workspace.current_dir')
session_id=$(echo "$input" | jq -r '.session_id // "unknown"')
model=$(echo "$input" | jq -r '.model.display_name')
total_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
total_duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
api_duration_ms=$(echo "$input" | jq -r '.cost.total_api_duration_ms // 0')
lines_added=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
lines_removed=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')

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
                    shortcuts_indicator="🚨 MOCK"
                elif echo "$shortcuts_output" | grep -q "⚡ SHORTCUT"; then
                    shortcuts_indicator="⚡ SHORTCUT"
                elif echo "$shortcuts_output" | grep -q "🎯 SOLID"; then
                    shortcuts_indicator="🎯 SOLID"
                elif echo "$shortcuts_output" | grep -q "❓ UNKNOWN"; then
                    shortcuts_indicator="❓ UNKNOWN"
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

# PR link detection with caching
pr_display=""
if [[ -n "$git_branch" ]]; then
    pr_cache_file="$HOME/.claude/pr_cache_$(echo "${current_dir}_${git_branch}" | shasum -a 256 | cut -d' ' -f1)"
    pr_timestamp_file="${pr_cache_file}_ts"
    pr_cache_duration=60

    refresh_pr=false
    if [[ ! -f "$pr_timestamp_file" ]] || [[ ! -f "$pr_cache_file" ]]; then
        refresh_pr=true
    else
        last_pr_update=$(cat "$pr_timestamp_file" 2>/dev/null || echo "0")
        if (( current_time - last_pr_update > pr_cache_duration )); then
            refresh_pr=true
        fi
    fi

    if [[ "$refresh_pr" == "true" ]]; then
        pr_url=$(cd "$current_dir" && gh pr view --json url -q .url 2>/dev/null || echo "")
        echo "$pr_url" > "$pr_cache_file"
        echo "$current_time" > "$pr_timestamp_file"
    fi

    pr_url=$(cat "$pr_cache_file" 2>/dev/null)
    if [[ -n "$pr_url" ]]; then
        pr_number=$(echo "$pr_url" | grep -o '[0-9]*$')
        pr_display=" | 🔗 PR#${pr_number}"
    fi
fi

# Calculate additional metrics
basename=$(basename "$current_dir")
duration_hours=$(echo "scale=1; $total_duration_ms / 3600000" | bc -l 2>/dev/null || echo "0.0")
cost_per_hour=$(echo "scale=2; if ($duration_hours > 0) $total_cost / $duration_hours else 0" | bc -l 2>/dev/null || echo "0.00")

# Format costs
formatted_cost=$(printf "%.2f" "$total_cost" 2>/dev/null || echo "0.00")
formatted_cost_per_hour=$(printf "%.2f" "$cost_per_hour" 2>/dev/null || echo "0.00")

# Get context window usage - try JSON input first, then fallback to session file
context_used=$(echo "$input" | jq -r '.context.used // 0')
context_max=$(echo "$input" | jq -r '.context.max // 200000')

# Fallback: if JSON doesn't have context info, try session file
if [[ "$context_used" -eq 0 ]] && [[ -f "$current_session_file" ]]; then
    total_tokens=$(tail -50 "$current_session_file" | grep '"usage"' | tail -1 | \
        jq '.message.usage | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)' 2>/dev/null)
    if [[ -n "$total_tokens" && "$total_tokens" != "null" && "$total_tokens" -gt 0 ]]; then
        context_used=$total_tokens
        context_max=200000
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
    formatted_tokens="$((context_used / 1000000))M"
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

if [[ -n "$five_hour_pct" ]]; then
    five_hour_int=$(printf "%.0f" "$five_hour_pct")
    reset_str=""
    if [[ -n "$five_hour_reset" ]]; then
        reset_time=$(date -r "$five_hour_reset" +%H:%M 2>/dev/null)
        [[ -n "$reset_time" ]] && reset_str=" \033[2m↻ ${reset_time}\033[0m"
    fi
    limits_display="⏱️  5h $(mini_bar "$five_hour_int" 5) ${five_hour_int}%${reset_str}"
fi

if [[ -n "$seven_day_pct" ]]; then
    seven_day_int=$(printf "%.0f" "$seven_day_pct")
    [[ -n "$limits_display" ]] && limits_display="${limits_display} | "
    limits_display="${limits_display}📅 wk $(mini_bar "$seven_day_int" 5) ${seven_day_int}%"
fi

# MCP usage display - show which MCPs were used in this session
mcp_display=""
if [[ -f "$current_session_file" ]]; then
    used_mcps=$(grep -o '"name":"mcp__[^_]*' "$current_session_file" 2>/dev/null | \
        sed 's/"name":"mcp__//' | sort -u | tr '\n' ' ')
    if [[ -n "$used_mcps" ]]; then
        mcp_display="🔌 \033[32m${used_mcps}\033[0m"
    fi
fi

# Shorten model name (strip "Claude " prefix)
short_model=$(echo "$model" | sed 's/^Claude //')

# Build the complete status line
status_line="\033[1;32m➜\033[0m \033[36m${basename}\033[0m${git_info}${pr_display}"
status_line="${status_line} | \033[33m🤖 ${short_model}\033[0m"
status_line="${status_line} | \033[32m💰\$${formatted_cost}\033[0m"
status_line="${status_line} | \033[36m📝${lines_added}+/${lines_removed}-\033[0m"
status_line="${status_line} | 🧠 ${context_info}"

# Add usage limits if available
if [[ -n "$limits_display" ]]; then
    status_line="${status_line} | ${limits_display}"
fi

# Add shortcuts indicator if available
if [[ -n "$shortcuts_indicator" ]]; then
    status_line="${status_line} | \033[33m${shortcuts_indicator}\033[0m"
fi

# Add MCP display if available
if [[ -n "$mcp_display" ]]; then
    status_line="${status_line} | ${mcp_display}"
fi

echo -e "$status_line"
