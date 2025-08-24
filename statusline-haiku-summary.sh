#!/bin/bash

# Claude Code Status Line with Periodic Haiku Summary
# This script runs 'claude --model haiku -p' periodically and caches the result

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

# Cache configuration - use session_id for isolation
cache_file="$HOME/.claude/haiku_summary_cache_${session_id}"
cache_timestamp_file="$HOME/.claude/haiku_summary_timestamp_${session_id}"
cache_hash_file="$HOME/.claude/haiku_summary_hash_${session_id}"
cache_duration=300  # seconds (5 minutes)

# Check if we need to refresh the cache based on conversation changes
refresh_cache=false
current_time=$(date +%s)

# Get current conversation hash to detect changes
project_sessions_dir="$HOME/.claude/projects/$(echo "$current_dir" | sed 's|/|-|g')"
current_session_file="$project_sessions_dir/${session_id}.jsonl"
current_conversation_hash=""

if [[ -f "$current_session_file" ]]; then
    # Create hash of recent conversation (last 10 entries)
    current_conversation_hash=$(tail -10 "$current_session_file" | shasum -a 256 | cut -d' ' -f1)
fi

# Check if cache needs refresh
if [[ ! -f "$cache_timestamp_file" ]] || [[ ! -f "$cache_file" ]] || [[ ! -f "$cache_hash_file" ]]; then
    refresh_cache=true
else
    last_update=$(cat "$cache_timestamp_file" 2>/dev/null || echo "0")
    last_hash=$(cat "$cache_hash_file" 2>/dev/null || echo "")
    
    # Refresh if conversation changed OR if it's been too long since last check
    if [[ "$current_conversation_hash" != "$last_hash" ]] || (( current_time - last_update > cache_duration )); then
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
            # Get the specific session file for this instance
            current_session_file="$project_sessions_dir/${session_id}.jsonl"
            
            if [[ -f "$current_session_file" ]]; then
                # Extract both user inputs and Claude's responses from current session
                session_data=$(jq -r '
                    select(.type == "user" or (.type == "assistant" and .message.content != null)) |
                    if .type == "user" then
                        "Human: " + (.message.content | if type == "string" then . else .[0].text // "..." end)
                    elif .type == "assistant" then
                        "Claude: " + (.message.content[] | select(.type == "text") | .text)
                    else
                        empty
                    end
                ' "$current_session_file" 2>/dev/null | tail -8 | head -c 400)
                
                if [[ -n "$session_data" ]]; then
                    claude_context="Recent conversation: $session_data"
                fi
            fi
        fi
        
        # Create prompt based on actual conversation
        if [[ -n "$claude_context" ]]; then
            project_prompt="<conversation_context>
$claude_context
</conversation_context>

<task>
You are a progress tracker for software development sessions. Your job is to create a concise status summary for a developer.

Analyze the recent conversation between the human developer and Claude Code assistant. Focus on:
- What specific task or problem Claude has been helping with
- What actions Claude has taken (coding, debugging, analysis, etc.)
- Current progress or state

Output ONLY a 5-word phrase that captures what Claude has been working on. The phrase should:
- Be actionable and specific (not vague)
- Help the user track their development progress  
- Focus on the main activity, not side discussions

Examples of good 5-word summaries:
- \"Fixing authentication database connection bug\"
- \"Implementing user registration API endpoints\"
- \"Debugging React component rendering issues\"
- \"Setting up deployment pipeline configuration\"

Remember: Output EXACTLY 5 words, nothing more, nothing less.
</task>"
        else
            # Fallback - check for recent file activity as secondary indicator
            if cd "$current_dir" 2>/dev/null; then
                recent_files=$(find . -type f -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.md" -mmin -30 2>/dev/null | head -3 | sed 's|^\./||' | tr '\n' ', ')
                current_branch=$(git branch --show-current 2>/dev/null)
                
                if [[ -n "$recent_files" ]]; then
                    project_prompt="<context>
Project: $(basename "$current_dir")
Branch: $current_branch  
Recent files: ${recent_files%,}
</context>

<task>
You are a development progress tracker. Based on the project name, git branch, and recently modified files, create a 5-word summary of what development work is likely happening.

Output ONLY 5 words that describe the current development activity. Be specific and actionable.

Examples:
- \"Building user authentication system components\"
- \"Refactoring database connection handling logic\" 
- \"Testing API endpoint response validation\"
</task>"
                else
                    project_prompt="<context>
Project: $(basename "$current_dir")
Branch: $current_branch
</context>

<task>
Based on the project name and git branch, create a 5-word summary of what development work is likely happening.

Output ONLY 5 words that describe the development activity.
</task>"
                fi
            else
                project_prompt="<task>
Create a generic 5-word summary for active development work.

Output ONLY 5 words like \"Working on development project tasks\"
</task>"
            fi
        fi
        
        haiku_output=$(echo "$project_prompt" | claude --model haiku -p 2>/dev/null)
        if [[ $? -eq 0 && -n "$haiku_output" ]]; then
            # Get first line and truncate to 50 characters
            haiku_summary=$(echo "$haiku_output" | head -n1 | cut -c1-50)
            echo "$haiku_summary" > "$cache_file"
            echo "$current_time" > "$cache_timestamp_file"
            echo "$current_conversation_hash" > "$cache_hash_file"
        fi
    fi
fi

# Read the cached summary
haiku_summary=""
if [[ -f "$cache_file" ]]; then
    haiku_summary=$(cat "$cache_file" 2>/dev/null)
fi

# Generate shortcuts detection (separate cache for performance, session-isolated)
shortcuts_cache_file="$HOME/.claude/shortcuts_cache_${session_id}"
shortcuts_timestamp_file="$HOME/.claude/shortcuts_timestamp_${session_id}"
shortcuts_hash_file="$HOME/.claude/shortcuts_hash_${session_id}"
shortcuts_cache_duration=300  # Check every 5 minutes

shortcuts_indicator=""
refresh_shortcuts=false

# Check if shortcuts cache needs refresh (same hash logic as summary)
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
    # Change to dedicated summary directory to avoid polluting project history
    summary_dir="$HOME/.claude/statusline-summaries"
    if cd "$summary_dir" 2>/dev/null; then
        # Get Claude's recent conversation context (same as summary logic)
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

# Add shortcuts indicator if available  
if [[ -n "$shortcuts_indicator" ]]; then
    status_line="${status_line} | \033[33m${shortcuts_indicator}\033[0m"
fi

# Add haiku summary if available
if [[ -n "$haiku_summary" ]]; then
    status_line="${status_line} | \033[2;35m📋 ${haiku_summary}\033[0m"
fi

# Add last updated timestamp
if [[ -f "$cache_timestamp_file" ]]; then
    last_update_time=$(cat "$cache_timestamp_file" 2>/dev/null || echo "0")
    if [[ "$last_update_time" != "0" ]]; then
        # Format as readable time
        formatted_time=$(date -r "$last_update_time" "+%H:%M" 2>/dev/null || echo "??:??")
        status_line="${status_line} | \033[90m⏰ ${formatted_time}\033[0m"
    fi
fi

echo -e "$status_line"