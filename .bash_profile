# ~/.bash_profile
# Login-shell bootstrap: load generic profile, then interactive bash config.

[ -f "$HOME/.profile" ] && . "$HOME/.profile"

case $- in
  *i*) [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc" ;;
esac