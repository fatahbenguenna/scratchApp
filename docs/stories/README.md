# Stories de la V1 — index

- **Auteur :** 🏃 Bob, Scrum Master BMAD (issue #8)
- **Date :** 14 novembre 2026 ; bilan de clôture de la V1 le 16 novembre 2026
- **Sources :** [spécifications v2.1](../specs/scratchapp_specifications_v2_1.md) (font foi), [PRD](../bmad/prd.md) (stories et plan de livraison, section 8), [architecture v1.2](../bmad/architecture.md), [spécification UX v1.1](../bmad/front-end-spec.md), [validation PO](../bmad/po-validation.md) (décisions D-01 à D-61), [recette V1](../qa/recette-v1.md) et [gates QA](../qa/gates/), [matrice de traçabilité](../bmad/traceability.md).
- **Kanban :** une issue GitHub par story (#19 à #44) et par épopée (#13 à #18), **toutes fermées** ; jalons « Sprint 0 — Fondations », « Planification BMAD », « V1 — P0 jouable » et « V1 — P1 complète » **fermés** ; restent ouverts « V1 — Diffusion » (#131) et « V1.1 » (#73, #129).

Chaque fichier de story est **autoportant** : critères d'acceptation numérotés (avec SF, RM et scénarios Gherkin de la spec v2.1), tâches, Dev Notes (signatures des contrats, fichiers et propriétaires, règles temps réel, constantes, pièges connus, décisions du PO), tests (quoi, où, Linux ou macOS), dépendances et journal. Le fichier de story fait foi ; le corps de l'issue en est un résumé.

## Bilan de la V1 (clôture du 16 novembre 2026)

- **26 stories sur 26 au statut Done**, toutes fusionnées sur `main` et leurs issues fermées ; les six épopées (#13 à #18) sont fermées avec un bilan.
- **Gates QA** : 20 PASS et 6 CONCERNS acceptées par le PO (1.1 D-51, 2.1 D-54, 2.2 D-53, 3.1 D-50, 4.1 D-52, 6.3 D-60), conformément au DoD de `TEAM.md` (CONCERNS acceptée avec une issue de suivi).
- **Recette 6.3** (PR #127) : partie automatisable conforme (438 tests macOS, 247 sous Linux, self-test 12/12, 69 scénarios sur 128 prouvés en entier, aucune anomalie). La gate CONCERNS est acceptée pour la **livraison du développement** de la V1 (D-60).
- **Avant toute diffusion** (TestFlight, App Store, partage d'un build) : la recette humaine **#131** (Mac de recette avec une personne aux commandes, iPhone et iPad, matériel USB, dérive des horloges) doit être close avec une gate PASS, ou CONCERNS acceptée par le PO sur les résultats réels. C'est elle qui décide du PASS final (D-23 amendée par D-60).

## Index

| Story | Titre | Agent | Prio | Dépend de (outre 0.2) | Vague | Issue | Statut | PR | Gate QA | Fichier |
|---|---|---|---|---|---|---|---|---|---|---|
| 1.1 | Modèle physique de la platine : plateau, feutrine, disque et résistance | 💻 James | P0 | — | 1 | #19 | Done | #50 | CONCERNS acceptée (D-51) | [`1.1.platter-disc-physics.md`](1.1.platter-disc-physics.md) |
| 1.2 | Suivi d'angle du geste | 💻 Léa | P0 | — | 1 | #20 | Done | #65 | PASS | [`1.2.gesture-angle-tracking.md`](1.2.gesture-angle-tracking.md) |
| 1.3 | Voix de lecture : tête, bornes et interpolation | 💻 James | P0 | — | 1 | #21 | Done | #60 | PASS | [`1.3.playback-voice.md`](1.3.playback-voice.md) |
| 1.4 | Table de mixage : gains, courbe, hamster, coupures et limiteur | 💻 James | P0 | — | 2 | #22 | Done | #64 | PASS | [`1.4.mixer-core.md`](1.4.mixer-core.md) |
| 1.5 | ScratchEngine : deux platines, commandes et instantané | 💻 James | P0 | 1.1 (#19), 1.3 (#21), 1.4 (#22) | 2 | #23 | Done | #79 | PASS | [`1.5.scratch-engine.md`](1.5.scratch-engine.md) |
| 2.1 | Hôte AVAudioEngine et sortie temps réel | 💻 James | P0 | 1.5 (#23) | 3 | #24 | Done | #84 | CONCERNS acceptée (D-54) | [`2.1.audio-engine-host.md`](2.1.audio-engine-host.md) |
| 2.2 | Décodeur AVFoundation | 💻 Hugo | P0 | — | 2 | #25 | Done | #55 | CONCERNS acceptée (D-53) | [`2.2.avfoundation-decoder.md`](2.2.avfoundation-decoder.md) |
| 2.3 | Session audio, interruptions et changements de sortie | 💻 James | P1 | 2.1 (#24) | 4 | #26 | Done | #88 (partie 1), #113 (partie 2) | PASS | [`2.3.audio-session-routes.md`](2.3.audio-session-routes.md) |
| 2.4 | Self-test de scratch complet en CI | 💻 James | P0 | 1.5 (#23), 2.1 (#24), 3.3 (#30) | 3 | #27 | Done | #82 | PASS | [`2.4.scratch-selftest.md`](2.4.scratch-selftest.md) |
| 3.1 | Index de bibliothèque et empreinte SHA-256 | 💻 Hugo | P0 | — | 1 | #28 | Done | #46 | CONCERNS acceptée (D-50) | [`3.1.library-index-sha256.md`](3.1.library-index-sha256.md) |
| 3.2 | Import : copie atomique, validation et dédoublonnage | 💻 Hugo | P0 | 3.1 (#28) | 2 | #29 | Done | #62 | PASS | [`3.2.import-pipeline.md`](3.2.import-pipeline.md) |
| 3.3 | Son de démonstration | 💻 Hugo | P0 | — | 1 | #30 | Done | #48 | PASS | [`3.3.demo-sound.md`](3.3.demo-sound.md) |
| 3.4 | Préférences persistantes et écran Réglages | 💻 Hugo | P1 | 6.1 (#42), 5.1 (#39) | 4 | #31 | Done | #89 | PASS | [`3.4.preferences-settings.md`](3.4.preferences-settings.md) |
| 3.5 | Écran Bibliothèque | 💻 Hugo | P1 | 3.1 (#28), 3.3 (#30), 6.1 (#42) | 4 | #32 | Done | #78 | PASS | [`3.5.library-screen.md`](3.5.library-screen.md) |
| 4.1 | Platine : modèle de présentation, faux moteur et disque animé | 💻 Léa | P0 | — | 1 | #33 | Done | #49 | CONCERNS acceptée (D-52) | [`4.1.deck-view.md`](4.1.deck-view.md) |
| 4.2 | Table de mixage (vue) | 💻 Léa | P0 | 4.1 (#33) | 2 | #34 | Done | #72 | PASS | [`4.2.mixer-view.md`](4.2.mixer-view.md) |
| 4.3 | Saisie du disque : tactile, souris et trackpad | 💻 Léa | P0 | 1.2 (#20), 4.1 (#33) | 2 | #35 | Done | #77 | PASS | [`4.3.disc-input.md`](4.3.disc-input.md) |
| 4.4 | Dispositions iPhone et iPad | 💻 Léa | P0 | 4.1 (#33), 4.2 (#34), 4.3 (#35) | 3 | #36 | Done | #85 | PASS | [`4.4.adaptive-layouts.md`](4.4.adaptive-layouts.md) |
| 4.5 | Pitch, CUE et résistance | 💻 Léa | P1 | 4.1 (#33) | 4 | #37 | Done | #87 | PASS | [`4.5.pitch-cue-resistance.md`](4.5.pitch-cue-resistance.md) |
| 4.6 | Forme d'onde et needle drop | 💻 Léa | P1 | 4.1 (#33) | 4 | #38 | Done | #95 | PASS | [`4.6.waveform-needle-drop.md`](4.6.waveform-needle-drop.md) |
| 5.1 | Clavier et menus Mac | 💻 Léa | P0 | 4.1 (#33), 4.2 (#34) | 3 | #39 | Done | #80 | PASS | [`5.1.mac-keyboard-menus.md`](5.1.mac-keyboard-menus.md) |
| 5.2 | Glisser-déposer sur une platine | 💻 Hugo | P1 | 4.1 (#33), 6.1 (#42) | 3 | #40 | Done | #74 | PASS | [`5.2.drag-and-drop.md`](5.2.drag-and-drop.md) |
| 5.3 | Accessibilité : VoiceOver, actions et navigation clavier | 💻 Léa | P1 | 4.1 (#33), 4.2 (#34), 4.3 (#35), 4.4 (#36), 4.5 (#37), 4.6 (#38), 5.1 (#39) | 5 | #41 | Done | #100 | PASS | [`5.3.accessibility.md`](5.3.accessibility.md) |
| 6.1 | AppModel et parcours de chargement | 💻 Hugo | P0 | 3.2 (#29), 3.3 (#30), 4.1 (#33) | 3 | #42 | Done | #71 | PASS | [`6.1.app-model-loading.md`](6.1.app-model-loading.md) |
| 6.2 | Intégration complète de l'application | 💻 Hugo | P0 | 1.5 (#23), 2.1 (#24), 2.2 (#25), 4.1 (#33), 4.2 (#34), 4.3 (#35), 4.4 (#36), 5.1 (#39), 6.1 (#42) | 5 | #43 | Done | #99 | PASS | [`6.2.app-integration.md`](6.2.app-integration.md) |
| 6.3 | Recette V1 sur macOS | 🧪 Quinn | P0 | 2.4 (#27), 6.2 (#43), stories P1 : 2.3, 3.4, 3.5, 4.5, 4.6, 5.2, 5.3 | 5 | #44 | Done | #127 (appuis #118 et #124) | CONCERNS acceptée (D-60) | [`6.3.acceptance-macos.md`](6.3.acceptance-macos.md) |

**26 stories** : EP1 5, EP2 4, EP3 5, EP4 6, EP5 3, EP6 3 ; 19 P0 et 7 P1. Jalon « V1 — P0 jouable » : 18 stories (toutes les P0 sauf 6.3) ; jalon « V1 — P1 complète » : les 7 P1 et la recette 6.3.

## Épopées

| Épopée | Titre | Issue | Dev | État |
|---|---|---|---|---|
| EP1 | Cœur audio temps réel (physique des platines, rendu, table de mixage) | #13 | 💻 James ; 1.2 : 💻 Léa | fermée |
| EP2 | Moteur audio Apple (AVAudioEngine, décodage, session, self-test) | #14 | 💻 James ; 2.2 : 💻 Hugo | fermée |
| EP3 | Bibliothèque locale et préférences | #15 | 💻 Hugo | fermée |
| EP4 | Interface : platines, table de mixage, forme d'onde, dispositions | #16 | 💻 Léa | fermée |
| EP5 | Commandes Mac, glisser-déposer et accessibilité | #17 | 💻 Léa ; 5.2 : 💻 Hugo | fermée |
| EP6 | Intégration de l'application, cycle de vie et recette | #18 | 💻 Hugo + 🧪 Quinn | fermée |

## Suivis

### Traités pendant la V1

| Suivi | Objet | Story | Résolu par | Décision du PO |
|---|---|---|---|---|
| #51 | Index partiellement illisible : une copie `library.json.corrupt_N` de plus à chaque lancement | 3.1 | PR #62 | D-50 |
| #52 | Message pour un index de bibliothèque illisible | 3.1 | PR #56 | D-49 |
| #53 | CA 8 de 1.1 et scénario « Doigt fixe à résistance 100 % » | 1.1 | PR #56 | D-48 |
| #54 | Lissage de τ lors d'un changement brutal de résistance pendant la tenue | 1.1 | PR #93 | D-51 |
| #57 | Commandes appliquées en différé : START/STOP et suspension de la boucle d'affichage | 4.1 | PR #70 | D-52 |
| #58 | Spec UX à aligner sur 4.1 (identifiants, marge des platines) | 4.1 | PR #110 | D-52 |
| #61 | Décodage d'un vrai MP3 de 10 min (CA 7 de 2.2) | 2.2 | PR #115 | D-53 |
| #75 | Mini-graphique des gains de la courbe du crossfader | 4.2 | PR #109 | — |
| #90 | Self-test sur le graphe partagé `ScratchAudioGraph.offline` | 2.4 | PR #107 | — |
| #91 | Latence geste→son : tampon de 128 trames, 256 en repli | 2.1 | PR #117 | D-54 |
| #92 | Sonde de latence en régime appris | 2.1 | PR #105 | D-54, D-56 |
| #94 | Retouches de la gate de 4.5 | 4.5 | PR #95 | — |
| #96 | Événements système reçus pendant une interruption | 2.3 | PR #88 | D-55 |
| #97 | Retouches de la gate de 3.4 (préférences) | 3.4 | PR #108 | — |
| #102 | Needle drop annulé par le système, mesure de NFR4 en release | 4.6 | PR #111 | — |
| #103 | `check-no-network` : adresses distantes et `NSURLConnection` | 6.2 | PR #112 | — |
| #106 | Ordre de tabulation dans une platine | 5.3 | PR #128 | D-59 |
| #114 | Sonde de latence sur 8 phases touches/affichage | 2.1 | PR #122 | D-56 |
| #121 | Interruption « app suspendue » (iOS) prise pour une vraie interruption | 2.3 | PR #113 | — |
| #123 | Rejeu du doigt : retard indépendant de la phase touches/affichage | 2.1 (rejeu, EP1) | PR #125 | D-57 |

Sans issue dédiée : conformité des doubles de bibliothèque à `LibraryStoring.reconcile()` après 3.1 (PR #68) ; retouches de la gate de 5.2 (PR #83) ; appuis à la recette 6.3, mémoire NFR4 (PR #118) et `ScratchApp --latency-report` (PR #124).

### Ouverts

| Suivi | Objet | Milestone | Décision du PO |
|---|---|---|---|
| #131 | Recette humaine V1 : Mac de recette, iPhone et iPad, matériel ; décide du PASS final, bloque toute diffusion | V1 — Diffusion | D-60, D-61 (mesure de la dérive) |
| #73 | « Fichier inaccessible » (UX §8.3) sans cas d'erreur : affiché « Échec de l'import » | V1.1 | D-58 |
| #129 | Rejeu : estimation d'horloge sensible à la dérive horloge audio/système après une pause | V1.1 | D-61 (escalade en P0 avant la diffusion selon la mesure de #131) |

## Réaffectations (directive de l'orchestrateur, plan initial)

Pour raccourcir le chemin critique de James :

| Story | Avant | Après | Raison | Fichiers concernés |
|---|---|---|---|---|
| 1.2 Suivi d'angle du geste | James | **Léa** | elle en a besoin pour 4.3 | `Sources/ScratchCore/Gesture/` passe à Léa (Swift pur, tests Linux) ; emploi des touches prédites dans `Physics/FingerTrajectory.swift` (D-16) : modification transverse relue par James |
| 2.2 Décodeur AVFoundation | James | **Hugo** | il implémente la sonde dont l'import 3.2 a besoin | `Sources/ScratchAudio/AudioFileDecoder.swift` et ses tests passent à Hugo ; le reste de `ScratchAudio/` reste à James |
| 5.2 Glisser-déposer | Léa | **Hugo** | il possède le parcours d'import et l'`AppModel` | fichiers nouveaux dans `Sources/ScratchUI/Library/` ; une ligne dans `Deck/DeckView.swift` (Léa), signalée |

## Ordre de travail et vagues (plan initial)

Une story démarre dès que ses dépendances sont fusionnées ; les vagues sont des repères (PRD 8.1 et 8.2).

| Dev | Ordre recommandé |
|---|---|
| 💻 James | 1.1 → 1.3 → 1.4 → 1.5 → 2.1 → 2.4 → 2.3 |
| 💻 Léa | 4.1 → 1.2 → 4.2 → 4.3 → 5.1 → 4.4 → 4.5 → 4.6 → 5.3 |
| 💻 Hugo | 3.1 → 3.3 → 2.2 → 3.2 → 6.1 → 5.2 → 3.4 → 3.5 → 6.2 |
| 🧪 Quinn | gate de chaque PR, puis 6.3 |

Chemin critique : 0.2 → 1.1 → 1.3 → 1.4 → 1.5 → 2.1 → 2.4 et 6.2 → 6.3. Si 1.5, 2.1, 4.4 et 5.1 sont fusionnées avant que Hugo ait fini 5.2, il avance 6.2 (P0) devant 3.4 et 3.5 (P1).

**Vague 1 du plan** (dépendaient seulement de 0.2, fusionnée) : 1.1 (#19, James), 1.3 (#21, James, après 1.1), 4.1 (#33, Léa), 1.2 (#20, Léa, après 4.1), 3.1 (#28, Hugo), 3.3 (#30, Hugo, après 3.1). Les stories 2.2 (#25) et 1.4 (#22) ne dépendaient aussi que de 0.2 et suivaient dans l'ordre de leur développeur.

## Démarrer une story (pour les versions suivantes)

1. Lire le fichier de story en entier, puis les sections citées en références si besoin.
2. Passer l'issue en `status:in-progress` ; créer la branche `story/<id>-<slug>` depuis `main` à jour.
3. Rester dans ses dossiers (PRD 5.4) ; toute modification transverse ou de `Contracts/` se signale dans la PR (seul changement de contrat prévu : `LibraryStoring.reconcile()` en 3.1, D-11).
4. Un test XCTest par critère testable, nommé avec son identifiant (`test…_SF03`) ; `scripts/linux-test.sh` pour ScratchCore et ScratchLibrary ; la CI macOS pour ScratchAudio, ScratchUI et l'app.
5. Remplir « Dev Agent Record » ; ouvrir la PR (modèle du dépôt, `Closes #<issue>`), passer l'issue en `status:review` ; Quinn renseigne « QA Results » et la gate.

## Statuts

`Draft` (en rédaction) → `Approved` (décisions du PO intégrées, prête à développer) → `InProgress` → `Review` → `Done` (PR fusionnée, gate PASS ou CONCERNS acceptée par le PO avec une issue de suivi, issue fermée). Les 26 stories sont `Done` ; pour 6.3, la recette humaine qui reste est portée par #131 et ne fait plus partie de son DoD (D-60).
