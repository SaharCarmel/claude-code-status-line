# Changelog

## [2025-08-24] - Multi-Instance Support & Session Isolation

### Added
- **Multi-Instance Compatibility**: Full support for running multiple Claude Code instances simultaneously
- **Session-Isolated Caching**: Each instance maintains separate cache files using unique session IDs
- **Per-Instance Context**: Each status line shows data specific to its own session and conversation

### Changed
- **Session Detection Logic**: Uses specific `session_id` instead of "most recent session" detection
- **Cache File Naming**: Session-specific cache files prevent cross-instance conflicts
- **Context Analysis**: Each instance analyzes only its own conversation thread

### Fixed
- **Multi-Instance Conflicts**: Eliminated shared state issues when multiple instances run together
- **Context Confusion**: Each instance now shows accurate summaries for its own work
- **Cache Collisions**: Session-isolated caching prevents instances from overwriting each other's data

### Technical Details
- Summary cache: `haiku_summary_cache_${session_id}`
- Shortcuts cache: `shortcuts_cache_${session_id}`  
- Session file targeting: `${session_id}.jsonl`
- Extracts `session_id` from Claude Code JSON input for unique identification

## [2025-08-24] - Code Quality Detection System

### Added
- **🚨 Shortcuts Detection**: New status line section that monitors Claude's code quality
- **Real-time Quality Monitoring**: Detects when Claude uses mocks, takes shortcuts, or implements properly
- **Current Session Focus**: Analyzes only the active session since last user input for relevant context
- **Quality Indicators**: Four clear indicators (🚨 MOCK, ⚡ SHORTCUT, 🎯 SOLID, ❓ UNKNOWN)

### Changed
- **Session Analysis Logic**: Now focuses on current session only instead of last 2 sessions
- **Context Scope**: Analyzes all messages since the last user input for complete context
- **Visual Design**: Clean emoji-based indicators without text prefixes
- **Robust Extraction**: Uses pattern matching to ensure only valid indicators are displayed

### Fixed
- **Partial Text Display**: Resolved issue where status line showed incomplete text like "Looking at"
- **Irrelevant Context**: Removed analysis of old/unrelated sessions
- **Output Reliability**: Improved prompt engineering to ensure consistent indicator output

### Technical Details
- Shortcuts detection runs every 60 seconds with separate caching
- Uses current session JSONL file only
- Analyzes conversation thread from last user input onwards
- Employs strict prompt engineering with pattern-based extraction

## [2025-08-24] - Enhanced Prompt Engineering for Better Summaries

### Added
- **Enhanced Prompt Engineering**: Implemented Anthropic's latest best practices for Claude prompt engineering
- **XML-style Structure**: Uses `<conversation_context>` and `<task>` tags for better instruction clarity
- **Role-based Prompting**: Assigns Claude a specific role as "progress tracker for software development sessions"
- **Concrete Examples**: Provides specific examples of good 5-word summaries
- **Clear Success Criteria**: Explicit instructions for actionable, specific, progress-focused summaries

### Fixed
- **Truncated Summaries**: Resolved issue where summaries were being cut off (e.g. "I need permission to create the file. Once you gra")
- **Vague Output**: Improved summary quality by being more explicit about desired output format

### Changed
- **Prompt Structure**: Complete rewrite of summary generation prompts using structured XML tags
- **Output Requirements**: More explicit "Output ONLY a 5-word phrase" and "EXACTLY 5 words, nothing more, nothing less"
- **Context Analysis**: Better focus on specific tasks, actions taken, and current progress

## [2025-08-24] - Status Line Session History Fix

### Fixed
- **Major Bug**: Status line summaries were running from project directories and polluting project history with summary sessions
- **History Pollution**: Every status line update (every 30 seconds) was creating entries in the project's `--resume` history

### Changed
- **Isolated Summary Generation**: Status line summaries now run from dedicated `~/.claude/statusline-summaries` directory
- **Real Conversation Context**: Now reads actual conversation history from Claude Code session files instead of inferring from git status
- **Enhanced Context**: Includes both user inputs and Claude responses from recent sessions
- **Improved Accuracy**: Summary based on last 8 conversation exchanges (4 human-Claude pairs) from most recent 2 sessions
- **Output Format**: Changed from 3-6 words to exactly 5 words for consistency

### Technical Details
- Summary sessions are now created in separate folder: `~/.claude/projects/-Users-saharcarmel--claude-statusline-summaries`
- Reads session data from: `~/.claude/projects/-Users-saharcarmel-Code-Work-Legal-draft-driver-100x/*.jsonl`
- Uses `jq` to parse JSONL session files and extract conversation pairs
- Maintains 30-second cache duration for performance

### Benefits
- ✅ Project history stays clean and focused on actual work
- ✅ Status line shows what Claude Code is actually working on
- ✅ More accurate summaries based on real conversation context
- ✅ No more pollution of project's `--resume` command history