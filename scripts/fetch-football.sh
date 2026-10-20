#!/usr/bin/env bash
# Fetch football-graphs' game files from its GitHub release "games" and unpack
# them where nginx serves bennetto.com/football/games/. Run daily by the cron
# job that setup-server.sh installs, an hour after the release's daily build.
#
# The release holds one SEASON.tar per season. A season is fetched only when
# its asset has changed since the last fetch, so past seasons are downloaded
# once, and each one replaces the old directory whole, so nginx never serves a
# half-unpacked season.
#
# Usage: scripts/fetch-football.sh [DEST]    (default /var/www/football-games)

set -euo pipefail

DEST="${1:-/var/www/football-games}"
RELEASE=https://api.github.com/repos/jackbenn/football-graphs/releases/tags/games

# inside DEST, so that moving a season into place is a rename; nginx's
# autoindex leaves out dot names, so the page never sees this or the stamps
mkdir -p "$DEST"
work="$(mktemp -d "$DEST/.fetch.XXXXXX")"
trap 'rm -rf "$work"' EXIT

curl -fsSL "$RELEASE" |
  jq -r '.assets[] | select(.name | test("^[0-9]{4}\\.tar$")) | [.name, .updated_at, .browser_download_url] | @tsv' |
  while IFS=$'\t' read -r name updated url; do
    season="${name%.tar}"
    stamp="$DEST/.$season.updated"
    if [[ -d "$DEST/$season" && "$(cat "$stamp" 2>/dev/null)" == "$updated" ]]; then
      continue
    fi
    curl -fsSL -o "$work/$name" "$url"
    tar -xf "$work/$name" -C "$work"
    rm -rf "$DEST/.$season.old"
    [[ -d "$DEST/$season" ]] && mv "$DEST/$season" "$DEST/.$season.old"
    mv "$work/$season" "$DEST/$season"
    rm -rf "$DEST/.$season.old"
    echo "$updated" > "$stamp"
    echo "fetched $season ($updated)"
  done
