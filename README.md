# Claude Code Status Line

Enhanced status line for Claude Code that shows intelligent 5-word summaries based on your actual conversation history.

## 🚀 Major Updates

### Latest: Enhanced Prompt Engineering (Aug 2025)
- **Fixed truncated summaries** - no more cut-off text like "I need permission to create the file. Once you gra"
- **Smarter summaries** using Anthropic's latest prompt engineering best practices
- **XML-structured prompts** with role-based instructions for better accuracy
- **Progress-focused output** that helps you track what Claude has been working on

### Core Innovation: Real Conversation Analysis  
- **Reads actual session history** from your Claude Code conversations
- **Clean project history** - summaries run in isolation, won't pollute your `--resume` history
- **Context-aware** - analyzes both human inputs and Claude responses

## Features

- **Smart Context**: Reads your actual Claude Code conversation history instead of guessing from git status
- **Real Summaries**: Shows what Claude has been working on based on recent human inputs and Claude responses
- **Clean History**: Runs summaries from isolated directory to avoid polluting your project's `--resume` history
- **Rich Status Line**: Displays project info, costs, git status, and intelligent summary

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/SaharCarmel/claude-code-status-line.git
   cd claude-code-status-line
   ```

2. Run the install script:
   ```bash
   ./install.sh
   ```

3. Add the status line configuration to your `~/.claude/settings.json`:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/statusline-haiku-summary.sh"
     }
   }
   ```

4. Restart Claude Code to see the enhanced status line!

## What It Shows

The status line displays:
- 🏠 Project name and git branch (with dirty indicator ✗)
- 🤖 Current model
- 💰 Session cost
- 🔥 Cost per hour
- 📝 Lines added/removed
- 🧠 Context usage (tokens and percentage)
- ✨ **5-word summary of what Claude has been working on**

## Example

```
➜ my-project git:(feature-branch) ✗ 🤖 Sonnet 4 | 💰 $3.46 session | ◯ IDE | 🔥 $6.92/hr | 📝 319+/215- | 🧠 86,271 (43%) | Implementing new feature with API
```

## How It Works

- Reads your Claude Code session files from `~/.claude/projects/`
- Extracts recent conversation history (both human and Claude messages)
- Generates summaries using Claude Haiku model
- Updates every 30 seconds with intelligent caching
- Runs from dedicated `~/.claude/statusline-summaries/` to keep your project history clean

## Requirements

- Claude Code CLI
- `jq` (for JSON parsing)
- `bun` and `ccusage` (for token tracking)
- `bc` (for calculations)