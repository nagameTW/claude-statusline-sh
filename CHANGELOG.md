# Changelog

Notable changes to claude-statusline-sh. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Two-line status line for Claude Code. Line 1 shows the model and effort level, fast mode, the project, the git branch with commits ahead and behind and changed files, and lines added and removed. Line 2 shows a context bar, 5-hour and weekly usage with reset times, and a warning when the prompt cache has gone cold.
- Meters stay grey while usage is fine, and turn yellow at 60% and red at 80%.
- Three shades of grey on top of Claude Code's own grey set the reading order. The palette follows Claude Code's `theme` setting, and `CLAUDE_STATUSLINE_THEME` overrides it. State colours come from the terminal palette.
- In a narrow or split pane, each line gives up details step by step, so the usage meters stay visible down to about 35 columns.
- Widths are counted in characters even when the shell starts in the C locale, as Git Bash often does.
- Git status comes from a single `git status` call, cached for 5 seconds per directory, and never takes the index lock.
- `NO_COLOR` turns colour off.
- Windows support through Git Bash, tested in CI. Project names come out right from Windows paths, and `.gitattributes` keeps the scripts on LF line endings.
