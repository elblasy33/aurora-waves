#!/usr/bin/env bash
# Install or update the "Egypt Radio" plasmoid for the current user.
#   ./install.sh            install / update
#   ./install.sh --restart  ... and reload plasmashell so the new version shows immediately
set -e
cd "$(dirname "$0")"
if kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -q '^org.beso.egyptradio$'; then
    kpackagetool6 -t Plasma/Applet -u package
else
    kpackagetool6 -t Plasma/Applet -i package
fi
# a running playback service keeps the old code until it exits; stop it if idle
python3 -I package/contents/code/radioctl.py '{"cmd":"status"}' | grep -q '"state": "playing"' \
    || python3 -I package/contents/code/radioctl.py '{"cmd":"quit"}' >/dev/null 2>&1 || true
if [ "$1" = "--restart" ]; then
    systemctl --user restart plasma-plasmashell
    echo "Done — plasmashell reloaded."
else
    echo "Done. Reload plasmashell to see changes:  systemctl --user restart plasma-plasmashell"
fi
