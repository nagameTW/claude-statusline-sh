## What and why

<!-- What changes in the status line, and what problem it solves. Link the issue if there is one. -->

## Before and after

<!-- If the output changes, paste it from before and after your change:
     NO_COLOR=1 COLUMNS=100 bash claude-statusline.sh < your-input.json -->

## Checklist

- [ ] `./test.sh` passes, and a new case covers the new behavior
- [ ] `shellcheck claude-statusline.sh test.sh` is clean
- [ ] Still runs on bash 3.2, the macOS default (no `declare -A`, `${var,,}`, `mapfile` or namerefs)
- [ ] README updated if the output or the options changed
- [ ] `CHANGELOG.md` has an entry under `[Unreleased]`
