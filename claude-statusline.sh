#!/usr/bin/env bash
# shellcheck disable=SC2154 # model, ctx and the rest are assigned by eval
# claude-statusline-sh: a quiet, two-line statusline for Claude Code.
#
#   ● Opus 5.5 high  ·  my-app / main ↑1 ~3  ·  +126 -38
#     ctx ━━━━━━──── 58%  ·  5h 71% resets 13:58  ·  7d 41% resets Mon 09:00
#
# Claude Code pipes session JSON on stdin. Segments are ordered by
# priority: when a line is wider than the terminal, the rightmost ones
# drop first. Needs jq; git is optional. Set NO_COLOR to turn colour off.

# Colour carries state, not decoration: a meter stays grey until it
# needs attention. Grey comes in three steps. Claude Code draws the whole
# status line in its own mid grey and maps "default colour" back to it,
# so that grey is the middle step (labels), dim is the lowest (structure
# words, separators), and the top step (names, values) needs an explicit
# colour that depends on the theme. State colours are the terminal's own
# 16, so they follow its palette.
ACCENT='38;5;173' BOLD='1' MUTED='2'
GREEN='32' YELLOW='33' RED='31' BLUE='34'

WARN_AT=60 # a meter turns yellow here
BAD_AT=80  # a meter turns red here
GIT_TTL=5  # seconds a cached git lookup stays fresh
MARGIN=4   # columns left for Claude Code's own indent and padding
WIDE_GAP='  ·  ' TIGHT_GAP=' · ' # between segments, drawn dim
MAX_LEVEL=5 # highest compaction level; past it, segments drop off
NAME_MAX=16 # longest project name kept whole on a narrow pane

if ! command -v jq >/dev/null 2>&1; then
  printf 'claude-statusline: jq not found\n'
  exit 0
fi

# One jq call for every field. @sh quotes each value and every value is
# a scalar, so the eval below only ever assigns variables.
fields=$(jq -r '
  def str: if . == null then "" else tostring end;
  def num: if type == "number" then floor else "" end;
  def int: if type == "number" then floor else 0 end;
  @sh "model=\(.model.display_name | str | sub(" *\\(.*\\)$"; ""))",
  @sh "effort=\(.effort.level | str)",
  @sh "fast=\(.fast_mode == true)",
  @sh "project=\([.workspace.project_dir // .cwd | str | splits("[/\\\\]")] | last // "")",
  @sh "dir=\(.workspace.current_dir // .cwd | str)",
  @sh "ctx=\(.context_window.used_percentage | num)",
  @sh "fh=\(.rate_limits.five_hour.used_percentage | num)",
  @sh "fh_reset=\(.rate_limits.five_hour.resets_at | num)",
  @sh "sd=\(.rate_limits.seven_day.used_percentage | num)",
  @sh "sd_reset=\(.rate_limits.seven_day.resets_at | num)",
  @sh "cache_cold=\(.prompt_cache.caching_observed == true and .prompt_cache.warm == false)",
  @sh "added=\(.cost.total_lines_added | int)",
  @sh "removed=\(.cost.total_lines_removed | int)"
' 2>/dev/null) || exit 0
eval "$fields"

# CLAUDE_STATUSLINE_THEME wins; otherwise follow Claude Code's own theme setting.
theme=${CLAUDE_STATUSLINE_THEME:-$(jq -r '.theme // empty' "$HOME/.claude.json" 2>/dev/null)}
case $theme in
  light*) PRIMARY='38;5;236' ;;
  *) PRIMARY='38;5;251' ;;
esac

# ── helpers ──────────────────────────────────────────────────────────
# They set globals (c, b, t, branch, dirty) instead of printing, which
# saves a subshell per call; the script runs on every session event.

level_color() { # colour for a used percentage; none while it is fine
  if [ "$1" -ge "$BAD_AT" ]; then c=$RED
  elif [ "$1" -ge "$WARN_AT" ]; then c=$YELLOW
  else c=''; fi
}

reset_time() { # $1 epoch, $2 strftime format; BSD date, then GNU date
  t=$(LC_ALL=C date -r "$1" +"$2" 2>/dev/null || LC_ALL=C date -d "@$1" +"$2" 2>/dev/null)
}

git_info() { # branch, commits ahead/behind and changed files for $1
  branch='' ahead=0 behind=0 dirty=0
  [ -n "$1" ] && command -v git >/dev/null 2>&1 || return
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline-sh" cache now stamp line oid=''
  cache="$cache_dir/$(printf '%s' "$1" | cksum | cut -d' ' -f1)"
  now=$(date +%s)
  if [ -f "$cache" ] &&
    { read -r stamp; read -r branch; read -r ahead; read -r behind; read -r dirty; } <"$cache" &&
    [ $((now - ${stamp:-0})) -lt "$GIT_TTL" ]; then
    return
  fi
  branch='' ahead=0 behind=0 dirty=0
  # One call gives everything. --no-optional-locks: never take index.lock
  # away from a real git command running at the same time.
  while IFS= read -r line; do
    case $line in
      '# branch.head '*) branch=${line#'# branch.head '} ;;
      '# branch.oid '*) oid=${line#'# branch.oid '} ;;
      '# branch.ab '*)
        read -r ahead behind <<<"${line#'# branch.ab '}"
        ahead=${ahead#+} behind=${behind#-}
        ;;
      '#'*) ;;
      *) dirty=$((dirty + 1)) ;;
    esac
  done < <(git --no-optional-locks -C "$1" status --porcelain=v2 --branch 2>/dev/null)
  [ "$branch" = '(detached)' ] && branch=${oid:0:7}
  # A cache that cannot be written only costs speed, so failures are ignored.
  mkdir -p "$cache_dir" 2>/dev/null &&
    printf '%s\n' "$now" "$branch" "$ahead" "$behind" "$dirty" >"$cache.$$" 2>/dev/null &&
    mv -f "$cache.$$" "$cache" 2>/dev/null
}

# A segment is built from styled pieces. The plain copy is kept next to
# it so the width can be measured without stripping escape codes.
seg_txt='' seg_raw=''
segs_txt=() segs_raw=()
gap=$WIDE_GAP

piece() { # $1 SGR code (empty for none), $2 text
  seg_raw+=$2
  if [ -z "$1" ] || [ -n "${NO_COLOR:-}" ]; then
    seg_txt+=$2
  else
    seg_txt+=$'\033['"$1m$2"$'\033[0m'
  fi
}

push() { # close the segment being built
  [ -z "$seg_raw" ] && return
  segs_txt+=("$seg_txt")
  segs_raw+=("$seg_raw")
  seg_txt='' seg_raw=''
}

measure() { # $1 segment count; their width with gaps, into w
  local i
  w=0
  [ "$1" -gt 0 ] || return
  w=$((($1 - 1) * ${#gap}))
  for ((i = 0; i < $1; i++)); do w=$((w + ${#segs_raw[i]})); done
}

fit() { # $1 line builder, $2 indent: first level whose line fits, into lvl
  local max=$((${COLUMNS:-120} - MARGIN - ${#2}))
  for ((lvl = 0; lvl < MAX_LEVEL; lvl++)); do
    "$1" "$lvl"
    measure ${#segs_raw[@]}
    segs_txt=() segs_raw=()
    [ "$w" -le "$max" ] && return
  done
}

render() { # $1 indent; print the segments, dropping from the right if
  # even the last compaction level is too wide
  local indent=${1:-} max=$((${COLUMNS:-120} - MARGIN - ${#1})) n=${#segs_raw[@]} i out='' sep=$gap
  while [ "$n" -gt 1 ]; do
    measure "$n"
    [ "$w" -le "$max" ] && break
    n=$((n - 1))
  done
  # Claude Code trims plain leading spaces, so the indent goes out styled.
  if [ -z "${NO_COLOR:-}" ]; then
    sep=$'\033['"${MUTED}m$gap"$'\033[0m'
    [ -n "$indent" ] && indent=$'\033['"${MUTED}m$indent"$'\033[0m'
  fi
  for ((i = 0; i < n; i++)); do
    [ "$i" -gt 0 ] && out+=$sep
    out+=${segs_txt[i]}
  done
  [ -n "$out" ] && printf '%s%s\n' "$indent" "$out"
  segs_txt=() segs_raw=()
}

bar() { # $1 percent, $2 cells: heavy line for the used part, thin for the rest
  local filled=$(($1 * $2 / 100)) i used='' rest=''
  [ "$filled" -gt "$2" ] && filled=$2
  for ((i = 0; i < $2; i++)); do
    if [ "$i" -lt "$filled" ]; then used+='━'; else rest+='─'; fi
  done
  piece "${c:-$PRIMARY}" "$used"
  piece "$MUTED" "$rest"
}

quota() { # $1 label, $2 used %, $3 reset time, $4 level
  [ -z "$2" ] && return
  level_color "$2"
  piece '' "$1 "
  piece "$BOLD;${c:-$PRIMARY}" "$2%"
  # Reset times go first when space runs out, but a meter that needs
  # attention keeps its own until the last level.
  if [ -n "$3" ] && { [ "$4" -lt 2 ] || { [ "$4" -lt 5 ] && [ "$2" -ge "$WARN_AT" ]; }; }; then
    piece "$MUTED" ' resets '
    piece '' "$3"
  fi
  push
}

# ── the two lines ────────────────────────────────────────────────────
# A builder takes a level. Level 0 is the full line, level 1 tightens the
# gaps, and each level after gives up one more detail, so a split pane
# loses details before it loses a meter or the project name.
#   line 1: 2 lines changed, 3 effort, 4 long project name cut, 5 branch
#   line 2: 2 reset times of meters that are fine, 3 half the bar,
#           4 the bar, 5 the remaining reset times

line1() { # model, project and branch, lines changed
  gap=$WIDE_GAP
  [ "$1" -ge 1 ] && gap=$TIGHT_GAP
  piece "$ACCENT" '● '
  piece "$BOLD;$ACCENT" "$model"
  [ -n "$effort" ] && [ "$1" -lt 3 ] && piece '' " $effort"
  [ "$fast" = true ] && piece "$YELLOW" ' fast'
  push

  local name=$project
  [ "$1" -ge 4 ] && [ "${#name}" -gt "$NAME_MAX" ] && name="${name:0:$((NAME_MAX - 1))}…"
  piece "$PRIMARY" "$name"
  if [ -n "$branch" ] && [ "$1" -lt 5 ]; then
    piece "$MUTED" ' / '
    piece "$BLUE" "$branch"
    [ "$ahead" -gt 0 ] 2>/dev/null && piece "$YELLOW" " ↑$ahead"
    [ "$behind" -gt 0 ] 2>/dev/null && piece "$YELLOW" " ↓$behind"
    [ "$dirty" -gt 0 ] 2>/dev/null && piece "$YELLOW" " ~$dirty"
  fi
  push

  if [ "$1" -lt 2 ] && { [ "$added" -gt 0 ] || [ "$removed" -gt 0 ]; }; then
    piece "$GREEN" "+$added"
    piece "$RED" " -$removed"
    push
  fi
}

line2() { # context, usage limits, prompt cache
  gap=$WIDE_GAP
  [ "$1" -ge 1 ] && gap=$TIGHT_GAP
  if [ -n "$ctx" ]; then
    level_color "$ctx"
    piece '' 'ctx '
    if [ "$1" -lt 3 ]; then
      bar "$ctx" 10
      piece '' ' '
    elif [ "$1" -lt 4 ]; then
      bar "$ctx" 5
      piece '' ' '
    fi
    piece "$BOLD;${c:-$PRIMARY}" "$ctx%"
    push
  fi
  quota 5h "$fh" "$fh_time" "$1"
  quota 7d "$sd" "$sd_time" "$1"
  if [ "$cache_cold" = true ]; then
    piece "$YELLOW" 'cache cold'
    push
  fi
}

# Everything that forks runs once, before the builders are tried.
git_info "$dir"
fh_time='' sd_time=''
if [ -n "$fh_reset" ]; then reset_time "$fh_reset" '%H:%M' && fh_time=$t; fi
if [ -n "$sd_reset" ]; then reset_time "$sd_reset" '%a %H:%M' && sd_time=$t; fi

fit line1 ''
l1=$lvl
fit line2 '  '
l2=$lvl
# Both lines share one gap width so they still read as one block.
[ "$l1" -eq 0 ] && [ "$l2" -gt 0 ] && l1=1
[ "$l2" -eq 0 ] && [ "$l1" -gt 0 ] && l2=1

line1 "$l1"
render
# Indented two columns so line 2 lines up under the model name.
line2 "$l2"
render '  '

# render's last test fails when a line is empty; that must not turn
# into a non-zero exit, which blanks the whole status line.
exit 0
