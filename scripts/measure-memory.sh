#!/usr/bin/env bash
# Empreinte mémoire de ScratchApp (recette 6.3 CA 4 ; NFR4, D-21) : « Physical footprint » de
# `vmmap --summary`, la valeur du Moniteur d'activité, et son pic depuis le lancement.
#
# Usage :
#   scripts/measure-memory.sh --once        un relevé de l'app lancée
#   scripts/measure-memory.sh [intervalle]  un relevé toutes les `intervalle` secondes (2 par défaut)
#                                           jusqu'à la fermeture de l'app ; sortie CSV
#
# Procédure de recette (Mac Apple Silicon, app en release) : lancer l'app, puis ce script ; charger
# deux sons distincts de 10 min sur A et B, puis remplacer 20 fois un son. Objectifs : 650 Mo au plus
# avec les deux sons, empreinte stable après les remplacements. La CI exécute `--once` sur la scène de
# démonstration pour vérifier l'outil.
set -euo pipefail

pid=$(pgrep -x ScratchApp | head -1 || true)
if [ -z "$pid" ]; then
    echo "ScratchApp n'est pas lancée." >&2
    exit 1
fi

sample() {
    vmmap --summary "$pid" 2>/dev/null | awk -F': *' '
        /^Physical footprint:/ { footprint = $2 }
        /^Physical footprint \(peak\):/ { peak = $2 }
        END { if (footprint != "") print footprint ";" peak }'
}

if [ "${1:-}" = "--once" ]; then
    values=$(sample)
    if [ -z "$values" ]; then
        echo "vmmap n'a pas donné l'empreinte de ScratchApp ($pid)." >&2
        exit 1
    fi
    echo "ScratchApp ($pid) : empreinte ${values%%;*}, pic ${values#*;}"
    exit 0
fi

interval=${1:-2}
echo "heure;empreinte;pic"
while kill -0 "$pid" 2>/dev/null; do
    echo "$(date +%H:%M:%S);$(sample)"
    sleep "$interval"
done
