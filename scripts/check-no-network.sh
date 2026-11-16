#!/usr/bin/env bash
# Aucune API réseau dans l'app (SF-20, NFR6, NFR7 ; story 6.2 CA 6 ; #103).
#
# Échoue si, dans Sources/ ou App/ :
#   - une API réseau apparaît (URLSession, NSURLConnection, Network, WebKit…) ;
#   - une adresse http:// ou https:// apparaît : Data(contentsOf:), String(contentsOf:) ou
#     AVURLAsset suffisent à faire une requête à partir d'une URL distante. Seule exception : la
#     DTD Apple en tête des listes de propriétés (.plist, .xcprivacy, .entitlements) ;
# ou si un droit réseau du bac à sable macOS apparaît dans project.yml ou App/.
#
# Usage :
#   scripts/check-no-network.sh [racine]   contrôle (racine du dépôt par défaut)
#   scripts/check-no-network.sh --self-test
#       plante chaque motif interdit dans une copie temporaire et vérifie que le contrôle échoue,
#       pour qu'il ne puisse pas devenir silencieux. Exécuté par la CI avant le contrôle.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"

api='URLSession|NSURLSession|URLRequest|NSURLRequest|NSURLConnection|NWConnection|NWListener|NWBrowser|NWPathMonitor|CFNetwork|CFSocket|CFStreamCreatePairWithSocket|CFHTTP|WKWebView|SFSafariViewController|ASWebAuthenticationSession|import[[:space:]]+(Network|WebKit|SafariServices)\b'
remote='https?://'
dtd='^[^:]+\.(plist|xcprivacy|entitlements):[0-9]+:<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1\.0//EN" "http://www\.apple\.com/DTDs/PropertyList-1\.0\.dtd">$'
entitlement='com\.apple\.security\.network\.(client|server)'

check() {
    local root=$1 status=0 hits
    if grep -rnE "$api" "$root/Sources" "$root/App"; then
        echo "Échec : API réseau trouvée dans Sources/ ou App/ (SF-20, NFR6)." >&2
        status=1
    fi
    hits=$(grep -rnE "$remote" "$root/Sources" "$root/App" | grep -vE "$dtd" || true)
    if [ -n "$hits" ]; then
        echo "$hits"
        echo "Échec : adresse http:// ou https:// dans Sources/ ou App/ (NFR6)." >&2
        status=1
    fi
    if grep -rnE "$entitlement" "$root/project.yml" "$root/App"; then
        echo "Échec : droit réseau du bac à sable macOS déclaré (NFR6)." >&2
        status=1
    fi
    return "$status"
}

self_test() {
    local work failures=0
    work=$(mktemp -d)
    trap 'rm -rf "$work"' RETURN
    cp -R "$repo/Sources" "$repo/App" "$repo/project.yml" "$work/"
    if ! check "$work" > /dev/null 2>&1; then
        echo "Auto-test : la copie intacte du dépôt échoue déjà." >&2
        return 1
    fi
    # File (relative to the root) | planted line. Each case must make the check fail.
    local cases=(
        'Sources/Planted.swift|let session = URLSession.shared'
        'Sources/Planted.swift|let session = NSURLSession.sharedSession()'
        'Sources/Planted.swift|let request = URLRequest(url: url)'
        'Sources/Planted.swift|let connection = NSURLConnection()'
        'Sources/Planted.swift|import Network'
        'Sources/Planted.swift|import WebKit'
        'Sources/Planted.swift|let monitor = NWPathMonitor()'
        'Sources/Planted.swift|let data = try Data(contentsOf: URL(string: "https://example.com")!)'
        'Sources/Planted.swift|let text = try String(contentsOf: URL(string: "http://example.com/a.txt")!)'
        'App/Planted.swift|let asset = AVURLAsset(url: URL(string: "https://example.com/a.mp3")!)'
        'App/Planted.swift|// "http://www.apple.com/DTDs/PropertyList-1.0.dtd" outside a property list'
        'App/Planted.plist|<string>https://example.com</string>'
        'project.yml|        com.apple.security.network.client: true'
    )
    local entry file line
    for entry in "${cases[@]}"; do
        file=${entry%%|*}
        line=${entry#*|}
        printf '%s\n' "$line" >> "$work/$file"
        if check "$work" > /dev/null 2>&1; then
            echo "Auto-test : motif non détecté ($file) : $line" >&2
            failures=$((failures + 1))
        fi
        if [ "$file" = project.yml ]; then cp "$repo/project.yml" "$work/project.yml"; else rm "$work/$file"; fi
    done
    [ "$failures" -eq 0 ] || return 1
    echo "Auto-test : ${#cases[@]} motifs plantés, tous détectés ; la copie intacte passe."
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

if check "${1:-$repo}"; then
    echo "Aucune API réseau, aucune adresse distante ni droit réseau : Sources/, App/, project.yml."
else
    exit 1
fi
