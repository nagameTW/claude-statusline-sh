#!/usr/bin/env bash
# Runs claude-statusline.sh against fixed inputs. Exits non-zero if any case fails.
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export XDG_CACHE_HOME="$tmp/cache" TZ=UTC NO_COLOR=1 COLUMNS=200 CLAUDE_STATUSLINE_THEME=dark
failed=0

run() { "$BASH" "$here/claude-statusline.sh"; } # same bash that runs the tests

check() { # $1 case name, $2 expected, $3 actual
  if [ "$2" = "$3" ]; then
    echo "ok   $1"
  else
    printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"
    failed=1
  fi
}

plain="$tmp/plain" # not a git repository
mkdir "$plain"
full='{"model":{"display_name":"Opus 5.5 (1M context)"},"effort":{"level":"high"},"fast_mode":true,
  "workspace":{"current_dir":"'$plain'","project_dir":"/work/my-app"},
  "cost":{"total_lines_added":126,"total_lines_removed":38},
  "context_window":{"used_percentage":58.4,"context_window_size":1000000},
  "prompt_cache":{"caching_observed":true,"warm":false},
  "rate_limits":{"five_hour":{"used_percentage":71.2,"resets_at":1790000000},
                 "seven_day":{"used_percentage":41,"resets_at":1790300000}}}'

check 'full input' \
  "● Opus 5.5 high fast  ·  my-app  ·  +126 -38
  ctx ━━━━━───── 58%  ·  5h 71% resets 14:13  ·  7d 41% resets Fri 01:33  ·  cache cold" \
  "$(run <<<"$full")"

check 'start of session hides what is still unknown' \
  '● Sonnet 5  ·  plain' \
  "$(run <<<'{"model":{"display_name":"Sonnet 5"},"cwd":"'"$plain"'","context_window":{"used_percentage":null}}')"

check 'narrow terminal drops segments from the right' \
  "● Opus 5.5 high fast  ·  my-app
  ctx ━━━━━───── 58%" \
  "$(COLUMNS=40 run <<<"$full")"

check 'Windows path gives the folder name' '● Sonnet 5  ·  my-app' \
  "$(run <<<'{"model":{"display_name":"Sonnet 5"},"workspace":{"project_dir":"C:\\Users\\me\\my-app"}}')"

check 'invalid JSON prints nothing' '' "$(run <<<'not json')"

check 'missing jq says so' 'claude-statusline: jq not found' \
  "$(PATH=/nonexistent /bin/bash "$here/claude-statusline.sh" </dev/null)"

repo="$tmp/repo"
git init -q -b feat/x "$repo"
touch "$repo/untracked"
input='{"model":{"display_name":"Opus 5.5"},"workspace":{"current_dir":"'$repo'","project_dir":"'$repo'"}}'
check 'git branch and changed files' '● Opus 5.5  ·  repo / feat/x ~1' "$(run <<<"$input")"

git -C "$repo" checkout -q -b other
check 'git lookup is cached' '● Opus 5.5  ·  repo / feat/x ~1' "$(run <<<"$input")"
check 'fresh cache sees the new branch' '● Opus 5.5  ·  repo / other ~1' \
  "$(XDG_CACHE_HOME="$tmp/cache2" run <<<"$input")"

commit() { git -C "$repo" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m "$1"; }
commit one
git -C "$repo" checkout -q -b topic
commit two
git -C "$repo" branch -q -u other
check 'commits ahead of upstream' '● Opus 5.5  ·  repo / topic ↑1 ~1' \
  "$(XDG_CACHE_HOME="$tmp/cache3" run <<<"$input")"

colored=$(NO_COLOR='' run <<<"$full")
case $colored in
  *$'\033[1;33m71%'*$'\033[1;38;5;251m41%'*) check 'only meters that need attention get colour' yes yes ;;
  *) check 'only meters that need attention get colour' yes no ;;
esac
case $(CLAUDE_STATUSLINE_THEME=light NO_COLOR='' run <<<"$full") in
  *$'\033[38;5;236mmy-app'*) check 'light theme uses a dark primary grey' yes yes ;;
  *) check 'light theme uses a dark primary grey' yes no ;;
esac

exit "$failed"
