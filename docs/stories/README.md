# Stories de la V1 — index

- **Auteur :** 🏃 Bob, Scrum Master BMAD (issue #8)
- **Date :** 14 novembre 2026
- **Sources :** [spécifications v2.1](../specs/scratchapp_specifications_v2_1.md) (font foi), [PRD v1.1](../bmad/prd.md) (stories et plan de livraison, section 8), [architecture v1.2](../bmad/architecture.md), [spécification UX v1.1](../bmad/front-end-spec.md), [validation PO](../bmad/po-validation.md) (décisions D-01 à D-47), [matrice de traçabilité](../bmad/traceability.md).
- **Kanban :** une issue GitHub par story (#19 à #44) et par épopée (#13 à #18), jalons « V1 — P0 jouable » et « V1 — P1 complète ».

Chaque fichier de story est **autoportant** : critères d'acceptation numérotés (avec SF, RM et scénarios Gherkin de la spec v2.1), tâches, Dev Notes (signatures des contrats, fichiers et propriétaires, règles temps réel, constantes, pièges connus, décisions du PO), tests (quoi, où, Linux ou macOS), dépendances et journal. Le fichier de story fait foi ; le corps de l'issue en est un résumé.

## Index

| Story | Titre | Agent | Prio | Dépend de (outre 0.2) | Vague | Issue | Épopée | Fichier |
|---|---|---|---|---|---|---|---|---|
| 1.1 | Modèle physique de la platine : plateau, feutrine, disque et résistance | 💻 James | P0 | — | 1 | #19 | EP1 (#13) | [`1.1.platter-disc-physics.md`](1.1.platter-disc-physics.md) |
| 1.2 | Suivi d'angle du geste | 💻 Léa | P0 | — | 1 | #20 | EP1 (#13) | [`1.2.gesture-angle-tracking.md`](1.2.gesture-angle-tracking.md) |
| 1.3 | Voix de lecture : tête, bornes et interpolation | 💻 James | P0 | — | 1 | #21 | EP1 (#13) | [`1.3.playback-voice.md`](1.3.playback-voice.md) |
| 1.4 | Table de mixage : gains, courbe, hamster, coupures et limiteur | 💻 James | P0 | — | 2 | #22 | EP1 (#13) | [`1.4.mixer-core.md`](1.4.mixer-core.md) |
| 1.5 | ScratchEngine : deux platines, commandes et instantané | 💻 James | P0 | 1.1 (#19), 1.3 (#21), 1.4 (#22) | 2 | #23 | EP1 (#13) | [`1.5.scratch-engine.md`](1.5.scratch-engine.md) |
| 2.1 | Hôte AVAudioEngine et sortie temps réel | 💻 James | P0 | 1.5 (#23) | 3 | #24 | EP2 (#14) | [`2.1.audio-engine-host.md`](2.1.audio-engine-host.md) |
| 2.2 | Décodeur AVFoundation | 💻 Hugo | P0 | — | 2 | #25 | EP2 (#14) | [`2.2.avfoundation-decoder.md`](2.2.avfoundation-decoder.md) |
| 2.3 | Session audio, interruptions et changements de sortie | 💻 James | P1 | 2.1 (#24) | 4 | #26 | EP2 (#14) | [`2.3.audio-session-routes.md`](2.3.audio-session-routes.md) |
| 2.4 | Self-test de scratch complet en CI | 💻 James | P0 | 1.5 (#23), 2.1 (#24), 3.3 (#30) | 3 | #27 | EP2 (#14) | [`2.4.scratch-selftest.md`](2.4.scratch-selftest.md) |
| 3.1 | Index de bibliothèque et empreinte SHA-256 | 💻 Hugo | P0 | — | 1 | #28 | EP3 (#15) | [`3.1.library-index-sha256.md`](3.1.library-index-sha256.md) |
| 3.2 | Import : copie atomique, validation et dédoublonnage | 💻 Hugo | P0 | 3.1 (#28) | 2 | #29 | EP3 (#15) | [`3.2.import-pipeline.md`](3.2.import-pipeline.md) |
| 3.3 | Son de démonstration | 💻 Hugo | P0 | — | 1 | #30 | EP3 (#15) | [`3.3.demo-sound.md`](3.3.demo-sound.md) |
| 3.4 | Préférences persistantes et écran Réglages | 💻 Hugo | P1 | 6.1 (#42), 5.1 (#39) | 4 | #31 | EP3 (#15) | [`3.4.preferences-settings.md`](3.4.preferences-settings.md) |
| 3.5 | Écran Bibliothèque | 💻 Hugo | P1 | 3.1 (#28), 3.3 (#30), 6.1 (#42) | 4 | #32 | EP3 (#15) | [`3.5.library-screen.md`](3.5.library-screen.md) |
| 4.1 | Platine : modèle de présentation, faux moteur et disque animé | 💻 Léa | P0 | — | 1 | #33 | EP4 (#16) | [`4.1.deck-view.md`](4.1.deck-view.md) |
| 4.2 | Table de mixage (vue) | 💻 Léa | P0 | 4.1 (#33) | 2 | #34 | EP4 (#16) | [`4.2.mixer-view.md`](4.2.mixer-view.md) |
| 4.3 | Saisie du disque : tactile, souris et trackpad | 💻 Léa | P0 | 1.2 (#20), 4.1 (#33) | 2 | #35 | EP4 (#16) | [`4.3.disc-input.md`](4.3.disc-input.md) |
| 4.4 | Dispositions iPhone et iPad | 💻 Léa | P0 | 4.1 (#33), 4.2 (#34), 4.3 (#35) | 3 | #36 | EP4 (#16) | [`4.4.adaptive-layouts.md`](4.4.adaptive-layouts.md) |
| 4.5 | Pitch, CUE et résistance | 💻 Léa | P1 | 4.1 (#33) | 4 | #37 | EP4 (#16) | [`4.5.pitch-cue-resistance.md`](4.5.pitch-cue-resistance.md) |
| 4.6 | Forme d'onde et needle drop | 💻 Léa | P1 | 4.1 (#33) | 4 | #38 | EP4 (#16) | [`4.6.waveform-needle-drop.md`](4.6.waveform-needle-drop.md) |
| 5.1 | Clavier et menus Mac | 💻 Léa | P0 | 4.1 (#33), 4.2 (#34) | 3 | #39 | EP5 (#17) | [`5.1.mac-keyboard-menus.md`](5.1.mac-keyboard-menus.md) |
| 5.2 | Glisser-déposer sur une platine | 💻 Hugo | P1 | 4.1 (#33), 6.1 (#42) | 3 | #40 | EP5 (#17) | [`5.2.drag-and-drop.md`](5.2.drag-and-drop.md) |
| 5.3 | Accessibilité : VoiceOver, actions et navigation clavier | 💻 Léa | P1 | 4.1 (#33), 4.2 (#34), 4.3 (#35), 4.4 (#36), 4.5 (#37), 4.6 (#38), 5.1 (#39) | 5 | #41 | EP5 (#17) | [`5.3.accessibility.md`](5.3.accessibility.md) |
| 6.1 | AppModel et parcours de chargement | 💻 Hugo | P0 | 3.2 (#29), 3.3 (#30), 4.1 (#33) | 3 | #42 | EP6 (#18) | [`6.1.app-model-loading.md`](6.1.app-model-loading.md) |
| 6.2 | Intégration complète de l'application | 💻 Hugo | P0 | 1.5 (#23), 2.1 (#24), 2.2 (#25), 4.1 (#33), 4.2 (#34), 4.3 (#35), 4.4 (#36), 5.1 (#39), 6.1 (#42) | 5 | #43 | EP6 (#18) | [`6.2.app-integration.md`](6.2.app-integration.md) |
| 6.3 | Recette V1 sur macOS | 🧪 Quinn | P0 | 2.4 (#27), 6.2 (#43), stories P1 : 2.3, 3.4, 3.5, 4.5, 4.6, 5.2, 5.3 | 5 | #44 | EP6 (#18) | [`6.3.acceptance-macos.md`](6.3.acceptance-macos.md) |

**26 stories** : EP1 5, EP2 4, EP3 5, EP4 6, EP5 3, EP6 3 ; 19 P0 et 7 P1. Jalon « V1 — P0 jouable » : 18 stories (toutes les P0 sauf 6.3) ; jalon « V1 — P1 complète » : les 7 P1 et la recette 6.3.

## Épopées

| Épopée | Titre | Issue | Dev |
|---|---|---|---|
| EP1 | Cœur audio temps réel (physique des platines, rendu, table de mixage) | #13 | 💻 James ; 1.2 : 💻 Léa |
| EP2 | Moteur audio Apple (AVAudioEngine, décodage, session, self-test) | #14 | 💻 James ; 2.2 : 💻 Hugo |
| EP3 | Bibliothèque locale et préférences | #15 | 💻 Hugo |
| EP4 | Interface : platines, table de mixage, forme d'onde, dispositions | #16 | 💻 Léa |
| EP5 | Commandes Mac, glisser-déposer et accessibilité | #17 | 💻 Léa ; 5.2 : 💻 Hugo |
| EP6 | Intégration de l'application, cycle de vie et recette | #18 | 💻 Hugo + 🧪 Quinn |

## Réaffectations (directive de l'orchestrateur)

Pour raccourcir le chemin critique de James :

| Story | Avant | Après | Raison | Fichiers concernés |
|---|---|---|---|---|
| 1.2 Suivi d'angle du geste | James | **Léa** | elle en a besoin pour 4.3 | `Sources/ScratchCore/Gesture/` passe à Léa (Swift pur, tests Linux) ; emploi des touches prédites dans `Physics/FingerTrajectory.swift` (D-16) : modification transverse relue par James |
| 2.2 Décodeur AVFoundation | James | **Hugo** | il implémente la sonde dont l'import 3.2 a besoin | `Sources/ScratchAudio/AudioFileDecoder.swift` et ses tests passent à Hugo ; le reste de `ScratchAudio/` reste à James |
| 5.2 Glisser-déposer | Léa | **Hugo** | il possède le parcours d'import et l'`AppModel` | fichiers nouveaux dans `Sources/ScratchUI/Library/` ; une ligne dans `Deck/DeckView.swift` (Léa), signalée |

## Ordre de travail et vagues

Une story démarre dès que ses dépendances sont fusionnées ; les vagues sont des repères (PRD 8.1 et 8.2).

| Dev | Ordre recommandé |
|---|---|
| 💻 James | 1.1 → 1.3 → 1.4 → 1.5 → 2.1 → 2.4 → 2.3 |
| 💻 Léa | 4.1 → 1.2 → 4.2 → 4.3 → 5.1 → 4.4 → 4.5 → 4.6 → 5.3 |
| 💻 Hugo | 3.1 → 3.3 → 2.2 → 3.2 → 6.1 → 5.2 → 3.4 → 3.5 → 6.2 |
| 🧪 Quinn | gate de chaque PR, puis 6.3 |

Chemin critique : 0.2 → 1.1 → 1.3 → 1.4 → 1.5 → 2.1 → 2.4 et 6.2 → 6.3. Si 1.5, 2.1, 4.4 et 5.1 sont fusionnées avant que Hugo ait fini 5.2, il avance 6.2 (P0) devant 3.4 et 3.5 (P1).

**Prêtes pour la vague 1** (dépendent seulement de 0.2, fusionnée) : 1.1 (#19, James), 1.3 (#21, James, après 1.1), 4.1 (#33, Léa), 1.2 (#20, Léa, après 4.1), 3.1 (#28, Hugo), 3.3 (#30, Hugo, après 3.1). Les stories 2.2 (#25) et 1.4 (#22) ne dépendent aussi que de 0.2 et suivent dans l'ordre de leur développeur.

## Démarrer une story

1. Lire le fichier de story en entier, puis les sections citées en références si besoin.
2. Passer l'issue en `status:in-progress` ; créer la branche `story/<id>-<slug>` depuis `main` à jour.
3. Rester dans ses dossiers (PRD 5.4) ; toute modification transverse ou de `Contracts/` se signale dans la PR (seul changement de contrat prévu : `LibraryStoring.reconcile()` en 3.1, D-11).
4. Un test XCTest par critère testable, nommé avec son identifiant (`test…_SF03`) ; `scripts/linux-test.sh` pour ScratchCore et ScratchLibrary ; la CI macOS pour ScratchAudio, ScratchUI et l'app.
5. Remplir « Dev Agent Record » ; ouvrir la PR (modèle du dépôt, `Closes #<issue>`), passer l'issue en `status:review` ; Quinn renseigne « QA Results » et la gate.

## Statuts

`Draft` (en rédaction) → `Approved` (décisions du PO intégrées, prête à développer) → `InProgress` → `Review` → `Done` (PR fusionnée). Les 26 stories sont `Approved`.
