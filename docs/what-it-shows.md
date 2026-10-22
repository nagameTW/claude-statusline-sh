# What it shows

The statusline has two lines. If Claude Code has not sent a value yet, the statusline leaves it out. It does not show a zero.

## Line 1

- The model and its effort level.
- `fast`, when fast mode is on.
- The project.
- The git branch. Next to it, `↑2` means two commits not pushed yet, `↓1` means one commit to pull, and `~3` means three changed files. Untracked files count as changed.
- The lines Claude has added and removed in this session.

The line count comes from Claude Code, and it does not match `git diff`. It covers only what Claude changed with its edit tools, so shell commands and your own edits do not show up. It adds up every edit, so a line that changes twice counts twice. It keeps counting after you commit.

## Line 2

- `ctx`: how much of the context window is used.
- `5h` and `7d`: how much of your 5-hour and weekly limits you have used, and when each one resets.
- `cache cold`: the prompt cache has expired, so the next message must build it again.

The usage limits appear only on Pro and Max plans, after the first response in a session.

## Meter colours

A usage meter stays grey while usage is fine. It turns yellow at 60% and red at 80%. [Configuration](configuration.md#colours) describes the other colours.
