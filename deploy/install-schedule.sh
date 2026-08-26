#!/bin/bash
# Install (or remove) the scheduled watcher as a user launchd agent.
#
#   ./deploy/install-schedule.sh install
#   ./deploy/install-schedule.sh status
#   ./deploy/install-schedule.sh uninstall
#
# User-level agent: no sudo, nothing outside your home directory, and
# uninstall removes it completely.
set -euo pipefail

LABEL="za.sa-macro-brief.watch"
OS="$(uname -s)"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST_SRC="$PROJECT_ROOT/deploy/$LABEL.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/$LABEL.plist"

# Linux: cron. macOS: launchd. Windows: see README (Task Scheduler).
if [ "$OS" != "Darwin" ]; then
  PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  CRON_LINE="5 9,10,13 * * 1-5 $PROJECT_ROOT/deploy/watch.sh"
  CRON_LINE2="40 11 * * 1-5 $PROJECT_ROOT/deploy/watch.sh"
  case "${1:-}" in
    install)
      chmod +x "$PROJECT_ROOT/deploy/watch.sh"
      ( crontab -l 2>/dev/null | grep -v "deploy/watch.sh" ; \
        echo "$CRON_LINE" ; echo "$CRON_LINE2" ) | crontab -
      echo "Installed cron entries (weekdays 09:05, 10:05, 11:40, 13:05 local time)."
      echo "Set the machine's timezone to Africa/Johannesburg, or shift the hours."
      ;;
    uninstall)
      crontab -l 2>/dev/null | grep -v "deploy/watch.sh" | crontab -
      echo "Removed cron entries."
      ;;
    status)
      crontab -l 2>/dev/null | grep "deploy/watch.sh" || echo "not installed"
      tail -n 8 "$PROJECT_ROOT/output/logs/watch.log" 2>/dev/null || echo "(no runs yet)"
      ;;
    *) echo "usage: $0 {install|uninstall|status}" >&2; exit 2 ;;
  esac
  exit 0
fi

case "${1:-}" in
  install)
    mkdir -p "$HOME/Library/LaunchAgents" "$PROJECT_ROOT/output/logs"
    chmod +x "$PROJECT_ROOT/deploy/watch.sh"
    sed "s|__PROJECT_ROOT__|$PROJECT_ROOT|g" "$PLIST_SRC" > "$PLIST_DEST"
    launchctl unload "$PLIST_DEST" 2>/dev/null || true
    launchctl load "$PLIST_DEST"
    echo "Installed $LABEL"
    echo "  plist:   $PLIST_DEST"
    echo "  logs:    $PROJECT_ROOT/output/logs/watch.log"
    echo "  polls:   weekdays 09:05, 10:05, 11:40, 13:05 SAST"
    ;;
  uninstall)
    launchctl unload "$PLIST_DEST" 2>/dev/null || true
    rm -f "$PLIST_DEST"
    echo "Removed $LABEL"
    ;;
  status)
    # launchctl print is authoritative; `list` output format varies by macOS
    if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
      echo "loaded: $LABEL"
      launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null \
        | grep -E "^\s+(state|last exit code) " || true
    else
      echo "not loaded"
    fi
    echo
    echo "last watch results:"
    tail -n 8 "$PROJECT_ROOT/output/logs/watch.log" 2>/dev/null || echo "  (no runs yet)"
    ;;
  *)
    echo "usage: $0 {install|uninstall|status}" >&2
    exit 2
    ;;
esac
