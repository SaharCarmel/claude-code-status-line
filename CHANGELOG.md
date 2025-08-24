# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.2] - 2025-08-24

### Added
- 🍺 Homebrew distribution support via `saharcarmel/claude` tap
- Automatic dependency management through Homebrew formula
- Easy update mechanism: `brew upgrade claude-code-status-line`

### Changed
- README now promotes Homebrew as the recommended installation method
- Added Homebrew badge and benefits section

## [1.3.1] - 2025-08-24

### Added
- Last updated timestamp showing actual cache refresh time (⏰ HH:MM format)

### Changed
- Increased cache duration from 30 seconds to 5 minutes to reduce unnecessary API calls
- Improved change detection to only refresh when conversation actually changes

### Fixed
- Eliminated constant cache refreshing when no conversation activity occurs
- Removed confusing "fresh"/"age" display that was stuck showing "fresh"

## [1.3.0] - 2025-08-24

### Added
- Multi-instance compatibility for running multiple Claude Code sessions simultaneously
- Session-isolated caching using unique session IDs
- Per-instance context analysis for accurate status line data

### Changed
- Session detection logic now uses specific `session_id` instead of "most recent session"
- Cache file naming includes session ID to prevent cross-instance conflicts
- Context analysis focuses on individual conversation threads

### Fixed
- Multi-instance conflicts when running concurrent Claude Code sessions
- Context confusion between different project sessions
- Cache collisions that caused incorrect status line data

## [1.2.0] - 2025-08-24

### Added
- Real-time code quality detection system
- Four quality indicators: 🚨 MOCK, ⚡ SHORTCUT, 🎯 SOLID, ❓ UNKNOWN
- Current session focus for analyzing conversation since last user input
- Robust pattern matching for reliable indicator extraction

### Changed
- Session analysis now focuses on current session only
- Context scope analyzes all messages since last user input
- Visual design uses clean emoji-based indicators
- Extraction logic uses pattern matching instead of text truncation

### Fixed
- Partial text display issues (e.g., showing "Looking at" instead of proper indicators)
- Irrelevant context from old/unrelated sessions
- Inconsistent output from quality detection prompts

## [1.1.0] - 2025-08-24

### Added
- Enhanced prompt engineering using Anthropic's latest best practices
- XML-structured prompts with `<conversation_context>` and `<task>` tags
- Role-based prompting for progress tracking
- Concrete examples and clear success criteria in prompts

### Changed
- Complete rewrite of summary generation prompts
- More explicit output requirements for consistent 5-word summaries
- Better focus on specific tasks and current progress

### Fixed
- Truncated summaries that were cut off mid-sentence
- Vague output quality from summary generation
- Inconsistent response format from AI model

## [1.0.0] - 2025-08-24

### Added
- Intelligent 5-word summaries based on actual conversation history
- Real conversation analysis from Claude Code session files
- Dedicated summary generation directory to prevent history pollution
- Rich status line displaying project info, costs, git status, and AI summaries

### Fixed
- Status line summaries running from project directories
- History pollution in project's `--resume` command history
- Inaccurate summaries based on git status guessing

### Changed
- Summary generation isolated to `~/.claude/statusline-summaries` directory
- Context analysis includes both user inputs and Claude responses
- Output format standardized to exactly 5 words
- Improved accuracy with last 8 conversation exchanges analysis