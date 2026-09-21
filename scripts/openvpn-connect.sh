#!/usr/bin/env bash
# Duckybox — connect OpenVPN with a .ovpn profile.
# Usage: openvpn-connect /path/to/profile.ovpn
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  exec sudo -E "$0" "$@"
fi

profile="${1:-}"
if [[ -z "${profile}" || ! -f "${profile}" ]]; then
  echo "Usage: openvpn-connect /path/to/profile.ovpn" >&2
  exit 1
fi

echo "Connecting with ${profile} (Ctrl-C to disconnect)…"
exec openvpn --config "${profile}"
