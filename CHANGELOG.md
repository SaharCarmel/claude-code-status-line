# Changelog

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