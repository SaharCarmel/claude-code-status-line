#!/bin/bash
set -e

echo "Installing Claude Code Status Line..."

# Copy script
cp "$(dirname "$0")/statusline-haiku-summary.sh" ~/.claude/

# Create summary directory  
mkdir -p ~/.claude/statusline-summaries

echo "✅ Installed! Add to your ~/.claude/settings.json:"
echo '  "statusLine": {"type": "command", "command": "bash ~/.claude/statusline-haiku-summary.sh"}'