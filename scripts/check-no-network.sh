#!/usr/bin/env bash
# Aucune API réseau dans l'app (SF-20, NFR6, NFR7 ; story 6.2 CA 6).
#
# Échoue si une API réseau apparaît dans Sources/ ou App/, ou si un droit réseau du bac à sable
# macOS apparaît dans project.yml ou App/. Exécuté par le job Linux de la CI.
set -euo pipefail
cd "$(dirname "$0")/.."

api='URLSession|URLRequest|NWConnection|NWListener|NWBrowser|NWPathMonitor|CFNetwork|CFSocket|CFStreamCreatePairWithSocket|WKWebView|SFSafariViewController|ASWebAuthenticationSession|import[[:space:]]+(Network|WebKit|SafariServices)\b'
entitlement='com\.apple\.security\.network\.(client|server)'
status=0

if grep -rnE "$api" Sources App; then
    echo "Échec : API réseau trouvée dans Sources/ ou App/ (SF-20, NFR6)." >&2
    status=1
fi

if grep -rnE "$entitlement" project.yml App; then
    echo "Échec : droit réseau du bac à sable macOS déclaré (NFR6)." >&2
    status=1
fi

if [ "$status" -eq 0 ]; then
    echo "Aucune API réseau ni droit réseau : Sources/, App/, project.yml."
fi
exit "$status"
