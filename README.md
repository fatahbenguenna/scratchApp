# ScratchApp

Double platine vinyle 33⅓ tours virtuelle avec table de mixage, pour **scratcher** ses propres sons
sur **iPhone (iOS 17+)**, **iPad (iPadOS 17+)** et **Mac (macOS 14+)**.

Le scratch n'est pas un effet préenregistré : la position et la vitesse de chaque disque pilotent
en temps réel la lecture (avant / arrière) du son chargé, avec feutrine, couple moteur, résistance
du vinyle et crossfader de scratch.

## Documentation

| Document | Rôle |
|---|---|
| [Spécifications v2.1](docs/specs/scratchapp_specifications_v2_1.md) | Référence fonctionnelle (SF, RM, Gherkin) ; la v2.0 est archivée dans `docs/specs/archive/` |
| [Revue v1.9 → v2.0](docs/specs/REVUE_v1.9_vers_v2.0.md) | Incohérences corrigées, scénarios ajoutés, évolutions |
| [Validation PO](docs/bmad/po-validation.md) | Checklist PO, registre des décisions D-01 à D-47, verdict |
| [Équipe BMAD](docs/bmad/TEAM.md) | Rôles des 10 agents et processus de développement |
| `docs/bmad/` | Brief, PRD, spec UX, architecture, validation PO |
| `docs/stories/` | Stories de développement (une par issue GitHub) |

## Structure

```
Package.swift            ScratchKit (Swift Package)
Sources/ScratchCore      Physique des platines, rendu DSP, table de mixage — Swift pur, testé sous Linux
Sources/ScratchLibrary   Bibliothèque locale, copies, SHA-256, préférences — Foundation, testé sous Linux
Sources/ScratchAudio     AVAudioEngine, décodage, session audio, self-test — Apple uniquement
Sources/ScratchUI        SwiftUI : platines, table de mixage, bibliothèque — Apple uniquement
App/                     Points d'entrée iOS/iPadOS et macOS
project.yml              Projet Xcode (XcodeGen)
```

## Développer

```bash
# Mac
brew install xcodegen
xcodegen generate
open ScratchApp.xcodeproj        # schémas ScratchApp-macOS et ScratchApp-iOS
swift test                       # tests du package
```

```bash
# Linux (cœur uniquement), avec Docker
scripts/linux-test.sh
```

L'application macOS accepte `--selftest` : rendu audio hors ligne du pipeline de scratch,
rapport JSON et code de retour (utilisé par la CI).

## Intégration continue

Chaque PR exécute : tests Linux (ScratchCore, ScratchLibrary) ; sur macOS : `swift test`,
build de l'app macOS, build de l'app iOS (simulateur), self-test audio, lancement de l'app et
capture d'écran (publiée sur la branche `ci-shots/pr-<n>`). Un rapport est commenté sur la PR.
