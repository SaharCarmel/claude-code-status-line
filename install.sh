#!/bin/bash
set -e

echo "🚀 Installing Claude Code Status Line..."

# Create ~/.claude directory if it doesn't exist
mkdir -p ~/.claude

# Download the status line script
echo "📥 Downloading status line script..."
curl -sL https://raw.githubusercontent.com/SaharCarmel/claude-code-status-line/main/statusline-haiku-summary.sh -o ~/.claude/statusline-haiku-summary.sh

# Make it executable
chmod +x ~/.claude/statusline-haiku-summary.sh

# Create summary directory  
mkdir -p ~/.claude/statusline-summaries

echo "✅ Installation complete!"
echo ""
echo "📝 Next step: Add this to your ~/.claude/settings.json:"
echo ""
echo '  "statusLine": {'
echo '    "type": "command",'
echo '    "command": "bash ~/.claude/statusline-haiku-summary.sh"'
echo '  }'
echo ""
echo "🎉 Restart Claude Code to see intelligent 5-word summaries!"
echo "📖 Learn more: https://github.com/SaharCarmel/claude-code-status-line"