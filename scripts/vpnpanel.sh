#!/usr/bin/env bash
# Duckybox — show VPN IP (tun0) for the MATE Command panel applet

vpn_ip=$(ip -4 -o addr show tun0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)

if [[ -n "${vpn_ip}" ]]; then
  echo "VPN: ${vpn_ip}"
else
  echo "VPN: Disconnected"
fi
