# Turfbox bash additions — sourced from ~/.bashrc

# Orange terminal sequences
if [[ -f /opt/turfbox/sequences ]]; then
  # shellcheck disable=SC1091
  source /opt/turfbox/sequences 2>/dev/null || true
fi

# Banner on interactive shells
if [[ $- == *i* ]] && [[ -f /opt/turfbox/turfbox-banner.txt ]]; then
  if [[ -z "${TURFBOX_BANNER_SHOWN:-}" ]]; then
    export TURFBOX_BANNER_SHOWN=1
    printf '\e[38;2;255;106;0m'
    cat /opt/turfbox/turfbox-banner.txt
    printf '\e[0m\n'
  fi
fi

# Prompt with VPN IP
if [[ -x /opt/turfbox/vpnbash.sh ]]; then
  _turfbox_vpn() { /opt/turfbox/vpnbash.sh; }
  PS1='\[\e[38;2;255;106;0m\]┌──\[$(_turfbox_vpn)\](\[\e[1m\]\u@\h\[\e[0;38;2;255;106;0m\])-[\[\e[0m\]\w\[\e[38;2;255;106;0m\]]\n└─\[\e[1m\]\$\[\e[0m\] '
fi

# tmux config hint
export TMUX_TMPDIR="${TMUX_TMPDIR:-/tmp}"
