# Claude Code Status Line with Haiku Summary

A custom status line for Claude Code that displays all standard information plus AI-generated project summaries.

## Features

- **Complete status info**: directory, git branch, model, costs, IDE status, context window
- **Real token counts**: integrates with `ccusage` for accurate 🧠 usage tracking  
- **AI summaries**: shows what you're working on (refreshed every 30 seconds)
- **Color coded**: matches original Claude Code styling

## Display Format

```
➜ project-name git:(main) 🤖 Model | 💰 $3.65 session | ◯ IDE | 🔥 $7.33/hr | 📝 28+/6- | 🧠 81,102 (41%) | Working on legal document analysis...
```

## Setup

### 1. Install ccusage (required for accurate token counts)

```bash
bun add -g ccusage
```

### 2. Install the status line script

```bash
# Download the script
curl -o ~/.claude/statusline-haiku-summary.sh https://raw.githubusercontent.com/[USERNAME]/claude-code-status-line/main/statusline-haiku-summary.sh

# Make it executable
chmod +x ~/.claude/statusline-haiku-summary.sh
```

### 3. Update your Claude Code settings

Add this to your `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-haiku-summary.sh"
  }
}
```

## How it works

- Parses JSON input from Claude Code with session info
- Calls `ccusage` internally for real token usage data
- Runs `claude --model haiku -p` every 30 seconds for project summaries
- Caches haiku responses to avoid excessive API calls
- Displays everything in a single colored status line

## Requirements

- Claude Code CLI
- `jq` (for JSON parsing)
- `bun` and `ccusage` (for token tracking)
- `bc` (for calculations)

## Customization

You can adjust these settings in the script:

- `cache_duration=30` - How often to refresh haiku summary (seconds)
- Haiku prompt: "Summarize what I'm working on in this project in 3-6 words"
- Color codes for different status elements

## License

MIT License - feel free to modify and share!