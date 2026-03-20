# ~/.bashrc
# Interactive shell configuration.
# Keep this file fast: guard non-interactive shells and lazy-load heavy tooling.
#
# Optional timing output:
#   export BASH_STARTUP_TIMING=1
# Prints per-section + total timings when .bashrc is loaded.

# Exit quickly when shell is non-interactive.
case $- in
  *i*) ;;
  *) return ;;
esac

# Timing helpers (enabled only when BASH_STARTUP_TIMING=1).
__bash_timing_enabled="${BASH_STARTUP_TIMING:-0}"
__bash_now_ms() {
  date +%s%3N 2>/dev/null || echo "$(( $(date +%s) * 1000 ))"
}
if [ "$__bash_timing_enabled" = "1" ]; then
  __bash_timing_start="$(__bash_now_ms)"
  __bash_timing_last="$__bash_timing_start"
fi
__bash_timing_mark() {
  [ "$__bash_timing_enabled" = "1" ] || return 0
  local now
  now="$(__bash_now_ms)"
  printf '[bashrc] %-14s +%4sms (total %4sms)\n' "$1" "$((now-__bash_timing_last))" "$((now-__bash_timing_start))"
  __bash_timing_last="$now"
}

# Command-exists helper.
has() {
  command -v "$1" >/dev/null 2>&1
}

# Prompt: starship (eager, lightweight in interactive sessions).
if has starship; then
  eval "$(starship init bash)"
fi
__bash_timing_mark "starship"

# eza replaces Terminal-Icons style listing for bash workflows.
if has eza; then
  alias ls='eza --group-directories-first --icons=auto'
  alias ll='eza --group-directories-first --icons=auto --long --header --git --time-style=long-iso'
  alias la='eza --group-directories-first --icons=auto --long --header --all --git --time-style=long-iso'
  alias lt='eza --group-directories-first --icons=auto --tree --level=2'
  alias tree='eza --group-directories-first --icons=auto --tree --level=2'
  alias l='ll'
fi
__bash_timing_mark "eza aliases"

# zoxide: lazy init on first z/zi call.
__zoxide_initialized=0
__init_zoxide_once() {
  [ "$__zoxide_initialized" -eq 1 ] && return 0
  __zoxide_initialized=1

  if has zoxide; then
    unset -f z zi 2>/dev/null
    eval "$(zoxide init bash)"
  fi
}

if has zoxide; then
  z() {
    __init_zoxide_once
    z "$@"
  }

  zi() {
    __init_zoxide_once
    zi "$@"
  }
fi
__bash_timing_mark "zoxide wrappers"

# fnm: eager init so globally installed npm binaries (codex, tsx, etc.) are in PATH.
if has fnm; then
  eval "$(fnm env --use-on-cd --version-file-strategy=recursive --shell bash)"
fi
__bash_timing_mark "fnm wrappers"

# fzf UI options: keep Ctrl+R / Ctrl+T / Alt+C consistent.
export FZF_CTRL_R_OPTS='--height 40% --layout=reverse --ansi'
export FZF_CTRL_T_OPTS='--height 40% --layout=reverse --ansi --preview "if [ -d {} ]; then if command -v eza >/dev/null 2>&1; then eza --group-directories-first --icons=always --color=always --long --all -- {}; else ls -lah -- {}; fi; else if command -v bat >/dev/null 2>&1; then bat --style=plain --color=always --line-range :200 -- {}; else head -n 200 -- {}; fi; fi" --preview-window=right,60%,border-left,wrap'
export FZF_ALT_C_OPTS='--height 40% --layout=reverse --ansi --preview "if command -v eza >/dev/null 2>&1; then eza --tree --level=2 --icons=always --color=always --group-directories-first --all -- {}; else ls -lah -- {}; fi" --preview-window=right,60%,border-left,wrap'

# fzf keybindings/completions (interactive only).
if has fzf; then
  eval "$(fzf --bash)"
fi
__bash_timing_mark "fzf"

__bash_timing_mark "done"

# Keep global namespace clean.
unset -f __bash_now_ms __bash_timing_mark
unset __bash_timing_enabled __bash_timing_start __bash_timing_last
