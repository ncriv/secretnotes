#!/bin/sh
# Launch SecretNotes (or any libsecret app) on a headless box with no desktop
# environment / keyring agent.
#
# flutter_secure_storage -> libsecret -> D-Bus Secret Service. With no DE there
# is nothing to unlock the keyring, so we spin up a private D-Bus session and
# run gnome-keyring inside it, unlocked with an EMPTY password. The "login"
# keyring is created with that empty password on first run and reused after.
#
# Usage:
#   ./run-linux-headless.sh                # runs the release bundle
#   ./run-linux-headless.sh flutter run -d linux   # or any command you pass
set -e

APP="build/linux/x64/release/bundle/secretnotes"
[ "$#" -gt 0 ] || set -- "$APP"

exec dbus-run-session -- sh -c '
  # Start gnome-keyring; capture the env vars it prints, unlock with empty pw.
  eval "$(printf "" | gnome-keyring-daemon --unlock --components=secrets,ssh)"
  export GNOME_KEYRING_CONTROL SSH_AUTH_SOCK
  exec "$@"
' sh "$@"
