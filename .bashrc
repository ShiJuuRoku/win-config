# --- Starship ---
eval "$(starship init bash)"

# --- FZF ---
[ -f ~/.fzf.bash ] && source ~/.fzf.bash

# --- Bat as cat replacement ---
alias cat='bat --paging=never'

# --- Exa as modern ls ---
alias ls='eza --git --icons'
alias ll='eza -l --git --icons'
alias tree='eza --tree --icons'

# --- Fuzzy history search (CTRL+R) ---
export FZF_CTRL_R_OPTS='--height 40% --layout=reverse --ansi'

# Optional: fast cd using fzf
fcd() {
  local dir
  dir=$(find . -type d 2> /dev/null | fzf +m) && cd "$dir"
}
alias cd='fcd'

eval "$(fnm env --use-on-cd --shell bash)"
