#!/usr/bin/env bash
# Pin every site's Python base image to the digest python:3.11-slim has on
# Docker Hub now. The Dockerfiles pin it so that the base changes only when
# this script is run, not whenever Docker Hub moves the tag: each change makes
# every image rebuild its pip layers and restarts every site. See INFRA-9.
#
# Usage: scripts/bump-python-base.sh     (from anywhere; needs curl, python3)
# Then commit (bookclub's Dockerfile is in its own repo) and deploy.
set -euo pipefail

TAG="3.11-slim"
INFRA="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILES=(
    "$INFRA/docker/gengo-web.Dockerfile"
    "$INFRA/docker/gengo-ws.Dockerfile"
    "$INFRA/docker/taking-the-story.Dockerfile"
    "$INFRA/bookclub/Dockerfile"
)

token=$(curl -fsS "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/python:pull" |
    python3 -c 'import json, sys; print(json.load(sys.stdin)["token"])')
# The multi-platform index digest, which is what `docker pull` resolves the tag to.
digest=$(curl -fsSI -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.oci.image.index.v1+json" \
    -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
    "https://registry-1.docker.io/v2/library/python/manifests/$TAG" |
    awk 'tolower($1) == "docker-content-digest:" { print $2 }' | tr -d '\r')
[[ "$digest" == sha256:* ]] || { echo "Error: no digest from Docker Hub" >&2; exit 1; }

echo "python:$TAG is $digest"
for f in "${FILES[@]}"; do
    grep -qE "^FROM python:$TAG(@sha256:[0-9a-f]{64})?$" "$f" ||
        { echo "Error: $f has no 'FROM python:$TAG' line" >&2; exit 1; }
    sed -i.bak -E "s|^FROM python:$TAG(@sha256:[0-9a-f]{64})?$|FROM python:$TAG@$digest|" "$f"
    rm -f "$f.bak"
    echo "  ${f#$INFRA/}"
done
