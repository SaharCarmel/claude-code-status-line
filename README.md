# Claude Code Status Line

Enhanced status line for Claude Code that shows intelligent 5-word summaries based on your actual conversation history.

## 🎯 See It In Action

```
➜ my-project git:(feature-branch) ✗ 🤖 Sonnet 4 | 💰 $3.46 session | ◯ IDE | 🔥 $6.92/hr | 📝 319+/215- | 🧠 86,271 (43%) | 🚨 MOCK | 📋 Implementing new feature with API
```

**What you get:**
- 🏠 Project name and git status
- 🤖 Current AI model  
- 💰 Session costs and performance
- 📝 Code changes tracking
- 🧠 Context window usage
- 🚨 **Code quality detection** - monitors if Claude is using mocks or taking shortcuts
- 📋 **Smart 5-word summary of what Claude is actually working on**

[![GitHub stars](https://img.shields.io/github/stars/SaharCarmel/claude-code-status-line?style=flat-square)](https://github.com/SaharCarmel/claude-code-status-line/stargazers)
[![Latest Release](https://img.shields.io/badge/version-v1.3.0-blue?style=flat-square)](https://github.com/SaharCarmel/claude-code-status-line/releases)
[![Changelog](https://img.shields.io/badge/changelog-Keep%20a%20Changelog-orange?style=flat-square)](CHANGELOG.md)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Compatible-purple?style=flat-square&logo=anthropic)](https://claude.ai/code)

## 🚀 Quick Install

### 🍺 Homebrew (Recommended)
```bash
brew tap saharcarmel/claude
brew install claude-code-status-line
```

**Benefits:**
- ✅ Automatic dependency management (`jq`, `node`)
- ✅ Easy updates: `brew upgrade claude-code-status-line` 
- ✅ Clean uninstall: `brew uninstall claude-code-status-line`
- ✅ Version tracking and rollbacks
- 🤖 **Auto-updating formula** - new releases automatically update Homebrew!

### 📥 One-Line Install (Alternative)
```bash
curl -sL https://raw.githubusercontent.com/SaharCarmel/claude-code-status-line/main/install.sh | bash
```

[![Homebrew](https://img.shields.io/badge/Install-Homebrew-orange?style=for-the-badge&logo=homebrew&logoColor=white)](https://github.com/SaharCarmel/homebrew-claude)
[![One-Line Install](https://img.shields.io/badge/Install-One%20Line-brightgreen?style=for-the-badge&logo=terminal&logoColor=white)](https://raw.githubusercontent.com/SaharCarmel/claude-code-status-line/main/install.sh)

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
- **Multi-instance ready** - works perfectly with multiple Claude Code sessions running simultaneously

### 🚨 Code Quality Detection
Monitor Claude's implementation approach in real-time:
- **🚨 MOCK** - Claude is using mock/fake data instead of real implementations
- **⚡ SHORTCUT** - Claude is taking implementation shortcuts or using placeholders  
- **🎯 SOLID** - Claude is implementing proper, production-ready solutions
- **❓ UNKNOWN** - Insufficient context to determine implementation quality

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


## How It Works

- Reads your Claude Code session files from `~/.claude/projects/`
- Extracts recent conversation history (both human and Claude messages)
- Generates summaries using Claude Haiku model
- Updates every 30 seconds with intelligent caching
- Runs from dedicated `~/.claude/statusline-summaries/` to keep your project history clean
- **Multi-instance isolation** - each Claude Code session gets its own status line data

## 📝 What's New

**Latest: v1.3.0** - Multi-Instance Support & Session Isolation
- ✅ Run multiple Claude Code sessions simultaneously without conflicts
- ✅ Each instance gets its own status line data and summaries
- ✅ Perfect isolation between different projects

**Recent Updates:**
- 🚨 **v1.2.0** - Real-time code quality detection system
- 🎯 **v1.1.0** - Enhanced prompt engineering for better summaries  
- 🚀 **v1.0.0** - Initial release with conversation-based summaries

➡️ **[View Full Changelog](CHANGELOG.md)** for complete version history

## 🍺 Homebrew Distribution

This project includes professional package management through Homebrew:

- **Homebrew Tap**: [`saharcarmel/homebrew-claude`](https://github.com/SaharCarmel/homebrew-claude)
- **Automated Updates**: GitHub Actions automatically update the Homebrew formula when new releases are created
- **Professional CI/CD**: Users get updates immediately after releases through `brew upgrade`

### For Developers
The repository includes automated Homebrew formula updates. See [`SETUP-AUTOMATION.md`](SETUP-AUTOMATION.md) for details on how the CI/CD pipeline works.

## Requirements

- Claude Code CLI
- `jq` (for JSON parsing) - *auto-installed with Homebrew*
- `bun` and `ccusage` (for token tracking)  
- `bc` (for calculations)