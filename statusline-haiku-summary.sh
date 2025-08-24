#!/bin/bash

# Claude Code Status Line with Periodic Haiku Summary
# This script runs 'claude --model haiku -p' periodically and caches the result

# Read JSON input from stdin
input=$(cat)
current_dir=$(echo "$input" | jq -r '.workspace.current_dir')
model=$(echo "$input" | jq -r '.model.display_name')
total_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
total_duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
api_duration_ms=$(echo "$input" | jq -r '.cost.total_api_duration_ms // 0')
lines_added=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
lines_removed=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')

# Cache configuration
cache_file="$HOME/.claude/haiku_summary_cache"
cache_timestamp_file="$HOME/.claude/haiku_summary_timestamp"
cache_duration=30  # seconds

# Check if we need to refresh the cache
refresh_cache=false
current_time=$(date +%s)

if [[ ! -f "$cache_timestamp_file" ]] || [[ ! -f "$cache_file" ]]; then
    refresh_cache=true
else
    last_update=$(cat "$cache_timestamp_file" 2>/dev/null || echo "0")
    if (( current_time - last_update > cache_duration )); then
        refresh_cache=true
    fi
fi

# Refresh cache if needed
if [[ "$refresh_cache" == "true" ]]; then
    # Change to dedicated summary directory to avoid polluting project history
    summary_dir="$HOME/.claude/statusline-summaries"
    mkdir -p "$summary_dir"
    if cd "$summary_dir" 2>/dev/null; then
        # Get Claude's recent outputs from session files
        claude_context=""
        
        # Build the project sessions path
        project_sessions_dir="$HOME/.claude/projects/$(echo "$current_dir" | sed 's|/|-|g')"
        
        if [[ -d "$project_sessions_dir" ]]; then
            # Get the most recent session files (last 2 sessions)
            recent_sessions=$(ls -t "$project_sessions_dir"/*.jsonl 2>/dev/null | head -2)
            
            if [[ -n "$recent_sessions" ]]; then
                # Extract both user inputs and Claude's responses from recent sessions
                conversation_context=""
                for session_file in $recent_sessions; do
                    # Get recent conversation pairs (user + assistant) - last 4 exchanges
                    session_data=$(jq -r '
                        select(.type == "user" or (.type == "assistant" and .message.content != null)) |
                        if .type == "user" then
                            "Human: " + (.message.content | if type == "string" then . else .[0].text // "..." end)
                        elif .type == "assistant" then
                            "Claude: " + (.message.content[] | select(.type == "text") | .text)
                        else
                            empty
                        end
                    ' "$session_file" 2>/dev/null | tail -8 | head -c 400)
                    
                    if [[ -n "$session_data" ]]; then
                        conversation_context="$conversation_context $session_data"
                    fi
                done
                
                if [[ -n "$conversation_context" ]]; then
                    claude_context="Recent conversation: $conversation_context"
                fi
            fi
        fi
        
        # Create prompt based on actual conversation
        if [[ -n "$claude_context" ]]; then
            project_prompt="$claude_context

Based on the recent conversation between human and Claude Code, summarize in exactly 5 words what Claude has been working on or helping with."
        else
            # Fallback - check for recent file activity as secondary indicator
            if cd "$current_dir" 2>/dev/null; then
                recent_files=$(find . -type f -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.md" -mmin -30 2>/dev/null | head -3 | sed 's|^\./||' | tr '\n' ', ')
                current_branch=$(git branch --show-current 2>/dev/null)
                
                if [[ -n "$recent_files" ]]; then
                    project_prompt="Project: $(basename "$current_dir"). Branch: $current_branch. Recent files: ${recent_files%,}

Based on the project context and recent activity, summarize in exactly 5 words what development work is happening."
                else
                    project_prompt="Working in project: $(basename "$current_dir") on branch: $current_branch

Based on this context, summarize in exactly 5 words what kind of development work this involves."
                fi
            else
                project_prompt="Development project in progress.

Summarize in exactly 5 words what kind of coding work this likely involves."
            fi
        fi
        
        haiku_output=$(echo "$project_prompt" | claude --model haiku -p 2>/dev/null)
        if [[ $? -eq 0 && -n "$haiku_output" ]]; then
            # Get first line and truncate to 50 characters
            haiku_summary=$(echo "$haiku_output" | head -n1 | cut -c1-50)
            echo "$haiku_summary" > "$cache_file"
            echo "$current_time" > "$cache_timestamp_file"
        fi
    fi
fi

# Read the cached summary
haiku_summary=""
if [[ -f "$cache_file" ]]; then
    haiku_summary=$(cat "$cache_file" 2>/dev/null)
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

# Calculate additional metrics
basename=$(basename "$current_dir")
duration_hours=$(echo "scale=1; $total_duration_ms / 3600000" | bc -l 2>/dev/null || echo "0.0")
cost_per_hour=$(echo "scale=2; if ($duration_hours > 0) $total_cost / $duration_hours else 0" | bc -l 2>/dev/null || echo "0.00")

# Format costs
formatted_cost=$(printf "%.2f" "$total_cost" 2>/dev/null || echo "0.00")
formatted_cost_per_hour=$(printf "%.2f" "$cost_per_hour" 2>/dev/null || echo "0.00")

# Get real context window usage from ccusage
ccusage_output=$(echo "$input" | bun x ccusage statusline 2>/dev/null)
if [[ -n "$ccusage_output" ]]; then
    # Extract context info from ccusage output
    context_info=$(echo "$ccusage_output" | grep -o "🧠 [0-9,]* ([0-9]*%)" | head -1)
    if [[ -z "$context_info" ]]; then
        # Fallback: estimate based on session activity
        estimated_tokens=$(echo "scale=0; 10000 + ($lines_added + $lines_removed) * 50" | bc -l 2>/dev/null || echo "15000")
        estimated_percentage=$(echo "scale=0; $estimated_tokens * 100 / 200000" | bc -l 2>/dev/null || echo "8")
        context_info="🧠 ${estimated_tokens} (${estimated_percentage}%)"
    fi
else
    # Fallback: estimate based on session activity
    estimated_tokens=$(echo "scale=0; 10000 + ($lines_added + $lines_removed) * 50" | bc -l 2>/dev/null || echo "15000")
    estimated_percentage=$(echo "scale=0; $estimated_tokens * 100 / 200000" | bc -l 2>/dev/null || echo "8")
    context_info="🧠 ${estimated_tokens} (${estimated_percentage}%)"
fi

# Build the complete status line similar to original
status_line="\033[1;32m➜\033[0m \033[36m${basename}\033[0m${git_info}"
status_line="${status_line} \033[33m🤖 ${model}\033[0m"
status_line="${status_line} | \033[32m💰 \$${formatted_cost} session\033[0m"
status_line="${status_line} | \033[34m◯ IDE\033[0m"
status_line="${status_line} | \033[35m🔥 \$${formatted_cost_per_hour}/hr\033[0m"
status_line="${status_line} | \033[36m📝 ${lines_added}+/${lines_removed}-\033[0m"
status_line="${status_line} | \033[37m${context_info}\033[0m"

# Add haiku summary if available
if [[ -n "$haiku_summary" ]]; then
    status_line="${status_line} | \033[2;35m${haiku_summary}\033[0m"
fi

echo -e "$status_line"