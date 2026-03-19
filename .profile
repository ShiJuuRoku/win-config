# ~/.profile
# Login-shell environment (shared base loaded by ~/.bash_profile).
# Keep this file lightweight and shell-agnostic.
#
# Optional timing output:
#   export BASH_STARTUP_TIMING=1
# Prints per-section + total timings when .profile is loaded.

__profile_timing_enabled="${BASH_STARTUP_TIMING:-0}"
__profile_now_ms() {
  date +%s%3N 2>/dev/null || echo "$(( $(date +%s) * 1000 ))"
}
__profile_timing_start="$(__profile_now_ms)"
__profile_timing_last="$__profile_timing_start"
__profile_timing_mark() {
  [ "$__profile_timing_enabled" = "1" ] || return 0
  local now
  now="$(__profile_now_ms)"
  printf '[profile] %-14s +%4sms (total %4sms)\n' "$1" "$((now-__profile_timing_last))" "$((now-__profile_timing_start))"
  __profile_timing_last="$now"
}

# Prepend path entry only if directory exists and is not already present.
path_prepend() {
  [ -d "$1" ] || return 0
  case ":$PATH:" in
    *":$1:"*) ;;
    *) PATH="$1:$PATH" ;;
  esac
}

path_prepend "$HOME/.local/bin"
path_prepend "$HOME/bin"
__profile_timing_mark "PATH"

export PATH
export EDITOR="${EDITOR:-vim}"
export VISUAL="${VISUAL:-$EDITOR}"
__profile_timing_mark "editor vars"

# History defaults (applies to bash sessions reading this file).
export HISTCONTROL=ignoredups:erasedups
export HISTSIZE=5000
export HISTFILESIZE=10000
__profile_timing_mark "history vars"

__profile_timing_mark "done"

# Keep global namespace clean.
unset -f __profile_now_ms __profile_timing_mark
unset __profile_timing_enabled __profile_timing_start __profile_timing_last