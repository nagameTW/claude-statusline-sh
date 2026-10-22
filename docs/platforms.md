# Platforms

## macOS and Linux

Both work, and WSL counts as Linux. CI runs the tests on Linux (bash 5, GNU `date`) and on macOS (bash 3.2, BSD `date`).

## Windows

Windows works through Git Bash. When Git Bash is installed, Claude Code runs status line commands with it. CI runs the tests there too.

1. Install `jq`. Git for Windows does not include it: `winget install jqlang.jq`.
2. Use forward slashes in the command path.

Without Git Bash, Claude Code falls back to PowerShell, which cannot run the script.
