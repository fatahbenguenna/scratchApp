#!/usr/bin/env bash
# Lance les tests du cœur (ScratchCore, ScratchLibrary) sous Linux avec l'image Swift officielle.
set -euo pipefail
cd "$(dirname "$0")/.."
ARGS=(--rm -v "$PWD:/w" -w /w)
if [ -n "${HTTPS_PROXY:-}" ]; then
  ARGS+=(--network host -e HTTPS_PROXY -e "https_proxy=$HTTPS_PROXY")
fi
if [ -f /root/.ccr/ca-bundle.crt ]; then
  ARGS+=(-v /root/.ccr/ca-bundle.crt:/ca.crt:ro -e GIT_SSL_CAINFO=/ca.crt -e SSL_CERT_FILE=/ca.crt)
fi
exec docker run "${ARGS[@]}" swift:6.0-jammy bash -c "swift test --parallel --scratch-path /w/.build-linux $*"
