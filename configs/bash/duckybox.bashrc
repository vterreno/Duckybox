# Duckybox bash additions — sourced from ~/.bashrc

# Violet terminal sequences
if [[ -f /opt/duckybox/sequences ]]; then
  # shellcheck disable=SC1091
  source /opt/duckybox/sequences 2>/dev/null || true
fi

# Banner on interactive shells
if [[ $- == *i* ]] && [[ -f /opt/duckybox/duckybox-banner.txt ]]; then
  if [[ -z "${DUCKYBOX_BANNER_SHOWN:-}" ]]; then
    export DUCKYBOX_BANNER_SHOWN=1
    printf '\e[38;2;167;139;250m'
    cat /opt/duckybox/duckybox-banner.txt
    printf '\e[0m\n'
  fi
fi

# Prompt with VPN IP
if [[ -x /opt/duckybox/vpnbash.sh ]]; then
  _duckybox_vpn() { /opt/duckybox/vpnbash.sh; }
  PS1='\[\e[38;2;167;139;250m\]┌──\[$(_duckybox_vpn)\](\[\e[1m\]\u@\h\[\e[0;38;2;167;139;250m\])-[\[\e[0m\]\w\[\e[38;2;167;139;250m\]]\n└─\[\e[1;38;2;124;58;237m\]\$\[\e[0m\] '
fi

export TMUX_TMPDIR="${TMUX_TMPDIR:-/tmp}"
