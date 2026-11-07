#!/bin/bash
# siteblock: system-wide site blocker for macOS (works in every browser).
# Layer 1: /etc/hosts  -> crypto, scam, gambling lists + custom.txt (TeraBox, DiskWala, ...)
# Layer 2: DNS 1.1.1.3 (Cloudflare for Families) -> adult + malware/phishing sites
# Usage: sudo ./siteblock.sh install | update | uninstall
set -euo pipefail

HOSTS="${HOSTS:-/etc/hosts}"          # override only for testing
HOME_DIR=/usr/local/siteblock
PLIST=/Library/LaunchDaemons/com.siteblock.update.plist
BEGIN="# >>> siteblock BEGIN"
END="# <<< siteblock END"
LISTS="https://blocklistproject.github.io/Lists/crypto.txt
https://blocklistproject.github.io/Lists/scam.txt
https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/gambling-only/hosts"
DNS4="1.1.1.3 1.0.0.3"
DNS6="2606:4700:4700::1113 2606:4700:4700::1003"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

need_root() { [ "${HOSTS}" != /etc/hosts ] || [ "$(id -u)" = 0 ] || { echo "Run with sudo."; exit 1; }; }

strip_block() { sed "/^${BEGIN}\$/,/^${END}\$/d" "$1"; }

update_hosts() {
  local tmp; tmp="$(mktemp)"
  {
    for url in $LISTS; do
      # keep only "0.0.0.0 domain" lines; a failed download aborts (set -e) so hosts is never half-written
      curl -fsSL --max-time 60 "$url" \
        | awk '$1=="0.0.0.0" && $2!="0.0.0.0" && $2 ~ /^[A-Za-z0-9.-]+$/ {print "0.0.0.0 " $2}'
    done
    grep -v '^\s*#' "$1" | tr -d ' \r' | grep . | while read -r d; do
      d="${d#www.}"; echo "0.0.0.0 $d"; echo "0.0.0.0 www.$d"
    done
  } | sort -u -k2,2 > "$tmp.body"
  [ -s "$tmp.body" ] || { echo "Block list empty, hosts not changed."; exit 1; }
  { strip_block "$HOSTS"; echo "$BEGIN"; cat "$tmp.body"; echo "$END"; } > "$tmp"
  cat "$tmp" > "$HOSTS"   # cat keeps file owner/permissions
  rm -f "$tmp" "$tmp.body"
  echo "Blocked $(grep -c '^0\.0\.0\.0' "$HOSTS") domains in $HOSTS"
  [ "$HOSTS" != /etc/hosts ] || { dscacheutil -flushcache; killall -HUP mDNSResponder 2>/dev/null || true; }
}

set_dns() {  # $@ = servers, or "Empty" to reset
  networksetup -listallnetworkservices | tail -n +2 | sed 's/^\*//' | while read -r svc; do
    networksetup -setdnsservers "$svc" "$@" 2>/dev/null && echo "DNS for '$svc': $*" || true
  done
}

case "${1:-}" in
  install)
    need_root
    mkdir -p "$HOME_DIR"
    cp "$SRC_DIR/siteblock.sh" "$SRC_DIR/custom.txt" "$HOME_DIR/"
    chmod 755 "$HOME_DIR/siteblock.sh"
    update_hosts "$HOME_DIR/custom.txt"
    set_dns $DNS4 $DNS6
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.siteblock.update</string>
  <key>ProgramArguments</key><array><string>$HOME_DIR/siteblock.sh</string><string>update</string></array>
  <key>StartInterval</key><integer>86400</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardErrorPath</key><string>/var/log/siteblock.log</string>
</dict></plist>
EOF
    launchctl bootout system "$PLIST" 2>/dev/null || true
    launchctl bootstrap system "$PLIST"
    echo "Installed. Lists refresh daily and DNS is re-applied."
    ;;
  update)
    need_root
    C="$HOME_DIR/custom.txt"; [ -f "$C" ] || C="$SRC_DIR/custom.txt"
    update_hosts "$C"
    [ "$HOSTS" != /etc/hosts ] || set_dns $DNS4 $DNS6
    ;;
  uninstall)
    need_root
    if [ "$HOSTS" = /etc/hosts ]; then
      launchctl bootout system "$PLIST" 2>/dev/null || true
      rm -f "$PLIST"
    fi
    tmp="$(mktemp)"; strip_block "$HOSTS" > "$tmp"; cat "$tmp" > "$HOSTS"; rm -f "$tmp"
    if [ "$HOSTS" = /etc/hosts ]; then
      set_dns Empty
      dscacheutil -flushcache; killall -HUP mDNSResponder 2>/dev/null || true
      rm -rf "$HOME_DIR"
    fi
    echo "Removed."
    ;;
  *) echo "Usage: sudo $0 install | update | uninstall"; exit 1 ;;
esac
