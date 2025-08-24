# Changelog

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