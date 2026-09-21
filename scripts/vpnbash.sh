#!/usr/bin/env bash
# Duckybox — VPN IP snippet for the bash prompt

vpn_ip=$(ip -4 -o addr show tun0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)

if [[ -n "${vpn_ip}" ]]; then
  echo -n "[VPN:${vpn_ip}]-"
fi
