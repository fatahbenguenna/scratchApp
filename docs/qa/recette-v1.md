# Recette V1 sur macOS (story 6.3)

| | |
|---|---|
| **Statut** | Trame préparée le 2026-11-16 ; exécution **à venir** |
| **Story** | [6.3](../stories/6.3.acceptance-macos.md) · issue #44 |
| **Recetteur** | 🧪 Quinn, avec l'appui de 💻 Hugo |
| **Démarrage** | Après la fusion de #113 (2.3 partie 2), #122 (#114, sonde sur 8 phases) et #117 (#91, tampon de 128 trames), ainsi que du correctif de #123 (rejeu), annoncé par James |
| **Commit de `main` recetté** | à renseigner au démarrage (rapport CI et self-test du même commit, CA 2) |
| **Références** | Spec v2.1 §6 (128 scénarios) et §7 ; traçabilité §5 à §7 ; D-01, D-14, D-15, D-21, D-23, D-44, D-46, D-53, D-54, D-56 |

## 1. Règles de recette

- **Périmètre.** 128 scénarios V1 : 61 P0 et 67 P1, dont les 3 scénarios `@P1` des features [P0], recettés avec le P1 (D-01). S'y ajoutent les critères de la spec §7.
- **Preuve.** Le nom exact du test XCTest (module.test) et le commit de `main`, le rapport du self-test, une capture ou un relevé dans `docs/qa/measurements/`. Une capture sans contexte ne suffit pas.
- **Mode** (colonne « Mode ») :
  - **Auto** : un test automatique couvre le scénario et cite son titre ;
  - **Auto (à confirmer)** : un test couvre l'exigence (traçabilité §2 et §3), mais le scénario doit être confirmé à la main ;
  - **Mac** : vérification manuelle sur le Mac de recette ;
  - **Appareil** : iPhone ou iPad physique (D-23).
- **Résultats** : ✅ conforme · ⚠️ réserve, avec issue · ❌ anomalie (issue `type:bug`) · 📱 à recetter sur appareil · 🚫 non testé, matériel indisponible · ⏳ à faire.
- **Gate** (CA 7) :
  - un scénario sur appareil non recetté, ou un objectif mesuré manqué, donne **CONCERNS** (D-23, D-15, D-21) ;
  - une anomalie P0 ouverte donne **FAIL** ;
  - pour la latence, une moyenne au-delà de l'objectif **plus une période d'image** (28,3 ms à 120 Hz, 46,7 ms à 60 Hz) donne une issue P0 et une décision du PO avant la livraison (D-56).

## 2. Critères de la spec §7

| # | Critère | Exigences (traçabilité §5) | Preuve prévue | Mode | Résultat |
|---|---|---|---|---|---|
| P0-1 | Importer un WAV (Finder sur Mac, Fichiers sur iOS) et obtenir un son lisible | SF-02, SF-03, SF-80 | Scénarios 6.1 ; import réel d'un WAV | Mac ; appareil | ⏳ |
| P0-2 | Charger deux sons sur deux platines indépendantes | SF-03, RM-57 | Scénarios 6.8 ; `AppModelLoadingTests` | Auto + Mac | ⏳ |
| P0-3 | START/STOP de chaque moteur à 33⅓ et 45 tours | SF-04, SF-05, SF-11 | Scénarios 6.2 | Auto + Mac | ⏳ |
| P0-4 | Retenir le disque sans saut, plateau en rotation (feutrine) | SF-06, SF-68, RM-03 | Scénarios 6.3 et 6.9 ; self-test (`platterSpinsWhileHeld`, `silentWhileHeldStill`) | Auto + Mac | ⏳ |
| P0-5 | Scratcher dans les deux sens, à plusieurs vitesses, moteur arrêté compris | SF-07 à SF-09, SF-77 | Scénarios 6.3 ; self-test (`rateSignFollowsGesture`, `noClickAtReversals`) | Auto + Mac | ⏳ |
| P0-6 | Relâcher le disque et retrouver 95 % de la vitesse en environ 60 ms | SF-10, SF-68 | `ScratchCore.testCatchUpReaches95PercentInSlipmatTime_SF10_SF68` ; self-test (`catchUpWithinSlipmatTime`) | Auto | ⏳ |
| P0-7 | Scratcher et utiliser le crossfader en même temps (souris et clavier sur Mac) | SF-12, SF-79, D-06 | Scénarios 6.4 et 6.14 | Mac ; appareil | ⏳ |
| P0-8 | Coupure franche : voie à plein niveau en 3 % de course au plus | SF-66, RM-52 | `ScratchCore.testCurveTable_6_10` ; self-test (`cutInWithin1ms`) | Auto | ⏳ |
| P0-9 | App macOS : compilation, tests et lancement en CI | NFR10 | Rapport CI de `main` et capture `ci-shots` | Auto | ⏳ |
| P1-1 | Résistance à 10 % et 90 %, réglage retrouvé au redémarrage | SF-21 à SF-24 | Scénarios 6.7 ; `AppModelPreferencesTests` ; relance de l'app | Auto + Mac | ⏳ |
| P1-2 | Pitch au pas de 0,1 %, remise à 0, CUE rappelé disque tenu compris | SF-11, SF-13 | Scénarios 6.6 | Auto + Mac | ⏳ |
| P1-3 | Repère et forme d'onde qui suivent le scratch ; needle drop | SF-69 à SF-71 | Scénarios 6.11 | Auto + Mac | ⏳ |
| P1-4 | Reculer dans l'amorce et atteindre le sillon fermé sans clic | SF-72, RM-55 | Scénarios 6.12 | Auto + Mac | ⏳ |
| P1-5 | Bibliothèque : recharger, supprimer, dédoublonner, nommer sans écraser, retirer une copie disparue | SF-73 à SF-75, RM-48, D-11 | Scénarios 6.13 | Auto + Mac | ⏳ |
| P1-6 | Sortie USB et changement de périphérique | SF-16, PO-08, D-04, D-44 | Section 4 | Mac matériel | ⏳ |
| P1-7 | Interruptions, arrière-plan, fichiers incorrects ou protégés, déconnexion USB sans plantage | SF-18, SF-81, SF-82, RM-56 | Scénarios 6.5 et 6.1 ; `AudioEngineHostSystemEventTests` (#113) | Auto + Mac ; appareil | ⏳ |
| P1-8 | Latence geste→son mesurée et consignée ; tampon ≤ 256 trames à 48 kHz | SF-78, D-15, D-54, D-56 | Section 3.1 | Mac | ⏳ |
| P1-9 | VoiceOver : toutes les commandes étiquetées | SF-83 | Scénarios 6.16 ; `AccessibilityTextTests` ; Accessibility Inspector | Auto + Mac ; appareil | ⏳ |

## 3. Mesures

### 3.1 Latence (CA 3 ; SF-78, D-15, D-54, D-56)

- **Sonde** : `AudioEngineHost.measureGestureLatency()` (#105, #122) sur le Mac de recette (Apple Silicon), app en **release**, sur la sortie intégrée puis sur l'interface USB.
- **Statistique de référence** : régime appris (second geste après échauffement), réponse au premier échantillon, **moyenne sur 8 phases** (milieux des intervalles d'une image), plus le tampon effectif et la latence de sortie annoncée. Le maximum et le premier geste sont consignés.
- **À relever pour chaque sortie** : tampon demandé et tampon effectif (`AudioOutputInfo.bufferFrames` ; 128 trames si #91 est retenu, sinon 256), fréquence, latence annoncée, moyenne et maximum à 120 Hz et à 60 Hz.
- **Objectifs** : moyenne ≤ 20 ms à 120 Hz et ≤ 30 ms à 60 Hz. Bluetooth et AirPlay sont consignés tels quels.
- **Repères déjà mesurés** (simulation sous Linux, un tampon compris, sans le périphérique) :

| Configuration | 120 Hz | 60 Hz |
|---|---|---|
| 256 trames | 25,6 ms | 34,2 ms |
| 128 trames, avant le correctif de #123 | 18,8 ms | 30,3 ms |
| 128 trames, après #125 (vérifié par la QA) | 17,0 ms (max 18,7 ms) | 25,0 ms (max 26,5 ms) |

- **Dérive des horloges (#129)** : pour chaque sortie, relever la dérive entre l'horloge audio et l'horloge système, soit `kAudioDevicePropertyActualSampleRate` comparée à la fréquence nominale, soit l'écart entre `mSampleTime` et `mHostTime` sur quelques minutes. La sonde ne simule aucune dérive. Si la dérive dépasse environ 20 ppm, faire une pause de 2 min puis un scratch, et vérifier la latence et l'absence de trou de vitesse au début du geste.
- **Facultatif** : mesure acoustique (micro sur le clic du trackpad et sur la sortie).

| Sortie | Tampon demandé → effectif | Fréquence | Dérive (ppm) | Latence annoncée | Moyenne 120 Hz | Max 120 Hz | Moyenne 60 Hz | Max 60 Hz | Résultat |
|---|---|---|---|---|---|---|---|---|---|
| Intégrée (Mac de recette) | | | | | | | | | ⏳ |
| Interface USB | | | | | | | | | ⏳ |

### 3.2 Mémoire et décodage (CA 4 ; NFR4, D-21, D-53)

- **Empreinte de l'app en release** : `scripts/measure-memory.sh` (#118) pendant le scénario suivant :
  1. charger deux sons distincts de 10 min sur A et B ;
  2. remplacer un son 20 fois.

  Objectifs : 650 Mo au plus, empreinte stable. Relevé CSV dans `docs/qa/measurements/`.
- **Repère CI** (processus de test, release) : +467 Mo, puis −3 Mo après 20 remplacements, et un pic de décodage de 1,00 × le clip (`MemoryFootprintTests`).
- **Décodage d'un MP3 de 10 min** : 0,34 s en release dans la CI (#115). En recette, mesurer en plus un vrai MP3 **stéréo à 320 kbit/s** (objectif : 3 s).

| Relevé | Valeur | Objectif | Résultat |
|---|---|---|---|
| Deux sons de 10 min chargés | | ≤ 650 Mo | ⏳ |
| Après 20 remplacements | | stable | ⏳ |
| MP3 stéréo à 320 kbit/s de 10 min, décodage | | ≤ 3 s | ⏳ |

## 4. Matériel (CA 5 ; PO-08, D-44, D-54)

| Essai | Attendu | Résultat |
|---|---|---|
| Interface USB (MPC Sample si disponible) : son, nom « … (USB) » dans le badge | SF-16, 6.5 | ⏳ |
| Interface multicanal (plus de 2 sorties), si disponible | Son sur les sorties 1-2 | ⏳ |
| Changement de sortie par défaut pendant la lecture | Son sur la nouvelle sortie, moteurs inchangés (D-04) | ⏳ |
| Interface USB retirée pendant la lecture | STOP, bandeau « Sortie audio déconnectée » ; aucun son sur les haut-parleurs (RM-56) | ⏳ |
| Démarrage sans sortie, puis branchement | « Sortie audio indisponible », puis nouvel essai et « Sortie audio disponible : … » (SF-82) | ⏳ |
| Veille et réveil du Mac | STOP à la veille ; aucune reprise au réveil | ⏳ |

## 5. À recetter sur appareil (CA 6 ; D-23)

Ces exigences ne se vérifient pas dans la CI, qui se limite au simulateur (traçabilité §7). Tant qu'elles ne sont pas recettées, la gate est CONCERNS et la réserve est consignée.

| Exigence | Points relevés par les gates (#44) | Résultat |
|---|---|---|
| SF-78 | Latence tactile (moyenne sur la phase) | 📱 |
| SF-19, D-05 | Trois contacts selon la disposition ; deux disques à la fois sur iPad | 📱 |
| SF-16, RM-56 | Casque débranché pendant la lecture (aucun son sur le haut-parleur) et pendant un appel | 📱 |
| SF-18, RM-10 | Appel entrant avec un disque tenu ; aucune reprise | 📱 |
| SF-81 | Arrière-plan pendant la lecture, retour, START : le son revient (#121) ; capture du sélecteur d'apps à STOP (D-54) | 📱 |
| D-37 | Écran allumé tant qu'un moteur tourne ou qu'un disque est tenu | 📱 |
| SF-06 à SF-10, SF-77, D-46 | Sensation et écoute critique ; rampe de résistance à 0,12 s/s ; calibrage avec un turntablist | 📱 |
| SF-70 | Bande zoomée sans image perdue à 120 Hz (Instruments) | 📱 |
| RM-60, RM-61 | Toucher annulé par le système ; rotation pendant un geste ou un needle drop (#111 : une fin normale place la tête) | 📱 |
| SF-73, SF-02 | Dépôt depuis Fichiers ; iCloud Drive ; fichier protégé réel | 📱 |
| SF-20 | Mode avion | 📱 |
| SF-83 | VoiceOver réel ; contraste augmenté ; ordre de lecture §11.3 | 📱 |
| 6.6, 6.7 | SET CUE et CUE d'un autre doigt, disque tenu ; résistance pendant un scratch | 📱 |

## 6. Scénarios Gherkin (spec v2.1 §6)

La colonne « Preuve prévue » vient d'un premier rapprochement automatique :

- **Auto** : un test qui cite le titre du scénario ;
- **Auto (à confirmer)** : un test qui porte l'identifiant d'une exigence liée par la traçabilité ;
- **sinon** : un rapprochement manuel.

Chaque ligne est confirmée pendant l'exécution.

### 6.1 Lancement et import

| # | Scénario | Prio | Exigences | Preuve prévue | Mode | Résultat |
|---|---|---|---|---|---|---|
| 6.1.1 | Premier lancement sans fichier | P0 | RM-01, SF-01, SF-76 | via exigence : ScratchUI.testDemoSceneOnlyWithItsLaunchArgument_RM01, ScratchLibrary.testDemoIsNeverLoadedAutomatically_RM01, ScratchCore.testEmptyDeckIsSilent_RM01 | Auto (à confirmer) + Mac | ⏳ |
| 6.1.2 | Importer un fichier WAV | P0 | RM-47, RM-57, SF-02, SF-03 | via exigence : ScratchLibrary.testImportCopiesHashesAndIndexes_SF02_RM47, ScratchUI.testSameClipIsAnalyzedOnce_RM57, ScratchUI.testImportLoadsOnOriginDeckOnly_SF02_RM57 | Auto (à confirmer) + Mac | ⏳ |
| 6.1.3 | Importer un format audio compatible | P0 | SF-02 | via exigence : ScratchUI.testImportLoadsOnOriginDeckOnly_SF02_RM57, ScratchAudio.testCompatibleFormatsDecode_SF02, ScratchLibrary.testImportCopiesHashesAndIndexes_SF02_RM47 | Auto (à confirmer) + Mac | ⏳ |
| 6.1.4 | Importer depuis le Finder sur Mac | P0 | RM-47, SF-02, SF-79 | via exigence : ScratchLibrary.testImportCopiesHashesAndIndexes_SF02_RM47, ScratchUI.testImportLoadsOnOriginDeckOnly_SF02_RM57, ScratchAudio.testCompatibleFormatsDecode_SF02 | Auto (à confirmer) + Mac | ⏳ |
| 6.1.5 | Recharger un son déjà importé sans accéder à Drive | P0 @P1 | RM-47, SF-74 | ScratchLibrary.testReloadDoesNotNeedTheSource_SF20 | Auto | ⏳ |
| 6.1.6 | Échec de copie faute d'espace | P0 | RM-48, SF-02 | ScratchLibrary.testInsufficientStorageLeavesNoTrace_6_1 | Auto | ⏳ |
| 6.1.7 | Un import ne modifie pas le fichier source | P0 | RM-47, SF-02 | ScratchLibrary.testSourceIsNeverModified_SF02 | Auto | ⏳ |
| 6.1.8 | Annuler l'importation | P0 | SF-02 | ScratchUI.testCancelledPickerChangesNothing_6_1 | Auto | ⏳ |
| 6.1.9 | Importer un fichier incompatible | P0 | RM-48, SF-02 | ScratchAudio.testNonAudioFileIsUnsupported | Auto | ⏳ |
| 6.1.10 | Importer un fichier protégé | P0 | SF-02 | ScratchAudio.testProtectedContentIsRejected | Auto | ⏳ |
| 6.1.11 | Importer un fichier corrompu ou vide | P0 | RM-48, SF-02 | ScratchAudio.testTruncatedAndEmptyFilesAreCorrupted | Auto | ⏳ |
| 6.1.12 | Importer un fichier trop long | P0 | SF-80 | ScratchAudio.testProbeRejectsTooLongAndTooShort_SF80 | Auto | ⏳ |
| 6.1.13 | Importer un contenu déjà présent dans la bibliothèque | P0 @P1 | RM-58, SF-75 | via exigence : ScratchLibrary.testIdentifiersAreStableAcrossReloads_RM58, ScratchLibrary.testSHA256OfficialVectors_RM58, ScratchLibrary.testMillionAInIrregularChunks_RM58 | Auto (à confirmer) + Mac | ⏳ |
| 6.1.14 | Charger le son de démonstration | P0 | SF-03, SF-76 | via exigence : ScratchUI.testJumpsRealignStickerAndLoadResetsDeck_SF03_SF69, ScratchUI.testPositionAndDurationFormats_SF03, ScratchCore.testLoadResetsDeckToInitialState_SF03 | Auto (à confirmer) + Mac | ⏳ |

### 6.2 Moteur et vitesses

| # | Scénario | Prio | Exigences | Preuve prévue | Mode | Résultat |
|---|---|---|---|---|---|---|
| 6.2.1 | Démarrer la platine à 33 tours | P0 | RM-02, SF-04 | ScratchCore.testStartReachesTargetInStartDuration_SF04_SF68 | Auto | ⏳ |
| 6.2.2 | Arrêter la platine | P0 | SF-05 | ScratchCore.testStopKeepsPositionAndTakesBrakeDuration_SF05 | Auto | ⏳ |
| 6.2.3 | Sélectionner 45 tours | P0 | RM-50, SF-04 | ScratchCore.testSpeedChangeWhileSpinningIsContinuous_SF11 | Auto | ⏳ |
| 6.2.4 | Modifier la vitesse pendant la lecture | P0 | RM-50, SF-04 | ScratchCore.testSpeedChangeWhileSpinningIsContinuous_SF11 | Auto | ⏳ |
| 6.2.5 | Démarrer sans fichier | P0 | RM-01, SF-01, SF-04 | ScratchUI.testStartOnEmptyDeckSpinsAndHighlights_PO01, ScratchCore.testPlatterSpinsWithoutClip_PO01, ScratchCore.testEmptyDeckIsSilentWithSpinningPlatter_RM01 | Auto | ⏳ |
| 6.2.6 | Appuyer sur STOP pendant que je retiens le disque | P0 | RM-03, RM-07, SF-05, SF-10 | ScratchCore.testStopWhileHeldNoRestart_RM07 | Auto | ⏳ |
| 6.2.7 | Appuyer sur START pendant le freinage | P0 | RM-08, SF-04 | ScratchCore.testStartDuringBrakingResumesFromCurrentSpeed | Auto | ⏳ |
| 6.2.8 | Régler les durées de démarrage et de freinage | P0 @P1 | SF-05, SF-68 | ScratchUI.testSettingsSettersQuantizeAndCommand | Auto | ⏳ |

### 6.3 Scratch tactile

| # | Scénario | Prio | Exigences | Preuve prévue | Mode | Résultat |
|---|---|---|---|---|---|---|
| 6.3.1 | Poser le doigt sur le disque | P0 | RM-03, RM-53, SF-06, SF-68 | via exigence : ScratchCore.testTouchHasPriorityOverMotor_RM03, ScratchCore.testPlatterIgnoresHold_RM53, ScratchCore.testGrabbingSpinningDiscHasNoPositionJump_SF06 | Auto (à confirmer) + Mac | ⏳ |
| 6.3.2 | Pousser le disque vers l'avant | P0 | RM-04, SF-07, SF-09 | via exigence : ScratchCore.testUnwrapsThreeTurns_RM04 | Auto (à confirmer) + Mac | ⏳ |
| 6.3.3 | Faire reculer le disque | P0 | RM-04, RM-05, SF-08, SF-09 | via exigence : ScratchCore.testUnwrapsThreeTurns_RM04, ScratchCore.testForwardAndBackwardReadTheLoadedClip_RM05 | Auto (à confirmer) + Mac | ⏳ |
| 6.3.4 | Faire un scratch avant-arrière | P0 | RM-08, SF-07, SF-08 | ScratchCore.testBabyScratchFollowsGestureAndReturnsToStart ; self-test `rateSignFollowsGesture` | Auto + Mac | ⏳ |
| 6.3.5 | Enchaîner des inversions rapides (baby scratch) | P0 | RM-08 | ScratchCore.testBabyScratchReturnsToStartWithin10ms_6_3 | Auto | ⏳ |
| 6.3.6 | Varier la vitesse du scratch | P0 | SF-09 | ScratchCore.testConstantGestureGivesContinuousVelocityAt120Hz_SF77 ; écoute | Auto + Mac | ⏳ |
| 6.3.7 | Maintenir un disque immobile | P0 | SF-06 | ScratchCore.testZeroSpeedIsSilent_6_3, ScratchCore.testFixedFingerStopsDisc_RM12 | Auto | ⏳ |
| 6.3.8 | Relâcher le disque moteur actif | P0 | RM-08, SF-10, SF-68 | ScratchCore.testCatchUpReaches95PercentInSlipmatTime_SF10_SF68 | Auto | ⏳ |
| 6.3.9 | Lancer le son depuis le repère (« release ») | P0 | SF-10 | via exigence : ScratchCore.testCatchUpReaches95PercentInSlipmatTime_SF10_SF68, ScratchCore.testCatchUpFromReverseMotion_SF10, ScratchCore.testFreeSpinStopsWithin150ms_SF10 | Auto (à confirmer) + Mac | ⏳ |
| 6.3.10 | Saisir le disque en rotation | P0 | SF-06 | ScratchCore.testGrabbingSpinningDiscHasNoPositionJump_SF06 | Auto | ⏳ |
| 6.3.11 | Scratcher avec le moteur arrêté | P0 | SF-05, SF-07, SF-08 | via exigence : ScratchUI.testToggleMotorSendsStartThenStop_SF04_SF05, ScratchUI.testStartStopReflectsCommandedState_SF04_SF05, ScratchCore.testStopKeepsPositionAndTakesBrakeDuration_SF05 | Auto (à confirmer) + Mac | ⏳ |
| 6.3.12 | Relâcher le disque moteur arrêté | P0 | RM-07, SF-10 | ScratchCore.testFreeSpinStopsWithin150ms_SF10 | Auto | ⏳ |
| 6.3.13 | Geste commencé hors du disque | P0 | — | ScratchCore.testGrabOnlyWhenStartingInsideGrabRadius_RM60, ScratchCore.testScrollStartedOutsideDoesNotGrab_RM60 | Auto + appareil | ⏳ |
| 6.3.14 | Deuxième doigt sur le même disque | P0 | — | ScratchUI.testContactAttributionAndSecondFingerIgnored_RM60 | Auto + appareil | ⏳ |
| 6.3.15 | Toucher annulé par le système | P0 | RM-60 | via exigence : ScratchUI.testContactAttributionAndSecondFingerIgnored_RM60, ScratchUI.testCancelReleasesTheDisc_RM60, ScratchUI.testCancellingReleasesAHeldDisc_RM60 | Auto (à confirmer) + Mac | ⏳ |
| 6.3.16 | Doigt posé au centre du disque | P0 | — | ScratchCore.testCenterDeadZoneFreezesAndResumesWithoutJump_RM61 | Auto + appareil | ⏳ |

### 6.4 Crossfader et table de mixage

| # | Scénario | Prio | Exigences | Preuve prévue | Mode | Résultat |
|---|---|---|---|---|---|---|
| 6.4.1 | Fermer complètement la voie A au crossfader | P0 | RM-06, SF-12 | ScratchCore.testMixerNeverMovesPlayback_RM06_SF12 | Auto | ⏳ |
| 6.4.2 | Ouvrir la voie A au crossfader | P0 | RM-06, SF-12 | via exigence : ScratchCore.testMixerNeverMovesPlayback_RM06_SF12 | Auto (à confirmer) + Mac | ⏳ |
| 6.4.3 | Ouvrir la voie avec un déplacement minimal (cut-in) | P0 | RM-52, SF-66 | ScratchCore.testHardCutReachesFullLevelWithin3Percent_SF66 | Auto | ⏳ |
| 6.4.4 | Scratch avec coupure rythmique | P0 | SF-12 | via exigence : ScratchCore.testMixerNeverMovesPlayback_RM06_SF12 | Auto (à confirmer) + Mac | ⏳ |
| 6.4.5 | Crossfader en position intermédiaire avec courbe douce | P0 | RM-06, SF-12, SF-66 | ScratchCore.testSoftCurveIsMinus3dBAtCenter_SF66 | Auto | ⏳ |
| 6.4.6 | Fader de voie | P0 | RM-06, RM-51, SF-65 | ScratchUI.testDeckChannelMeterFollowsTheSnapshotPeak, ScratchCore.testMixerNeverMovesPlayback_RM06_SF12, ScratchCore.testMetersArePublished_SF65 | Auto | ⏳ |

### 6.5 Cycle de vie et sortie audio

| # | Scénario | Prio | Exigences | Preuve prévue | Mode | Résultat |
|---|---|---|---|---|---|---|
| 6.5.1 | Charger un deuxième fichier sur une platine active | P1 | RM-57, SF-03, SF-15 | via exigence : ScratchUI.testSameClipIsAnalyzedOnce_RM57, ScratchUI.testImportLoadsOnOriginDeckOnly_SF02_RM57, ScratchCore.testSameClipOnBothDecks_RM57 | Auto (à confirmer) + Mac | ⏳ |
| 6.5.2 | Charger un deuxième fichier sur une platine à l'arrêt | P1 | SF-15 | via exigence : ScratchUI.testReplacementRules_SF15_D40, ScratchCore.testSnapshotActivityFlag_SF15, ScratchCore.testReplacingAPlayingSoundFadesOut_SF15 | Auto (à confirmer) + Mac | ⏳ |
| 6.5.3 | Refuser le remplacement | P1 | SF-15 | via exigence : ScratchUI.testReplacementRules_SF15_D40, ScratchCore.testSnapshotActivityFlag_SF15, ScratchCore.testReplacingAPlayingSoundFadesOut_SF15 | Auto (à confirmer) + Mac | ⏳ |
| 6.5.4 | Recevoir une interruption système (iPhone/iPad) | P1 | RM-10, RM-56, SF-18 | via exigence : ScratchUI.testLaunchAppliesPreferencesThenStartsHostWithoutPlayback_RM10, ScratchUI.testLaunchAppliesPreferencesWithoutPlayback_RM10, ScratchAudio.testStartNeverStartsMotors_RM10 | Auto (à confirmer) + Mac ; appareil | ⏳ |
| 6.5.5 | Passer en arrière-plan (iPhone/iPad) | P1 | RM-10, RM-56 | via exigence : ScratchUI.testLaunchAppliesPreferencesThenStartsHostWithoutPlayback_RM10, ScratchUI.testLaunchAppliesPreferencesWithoutPlayback_RM10, ScratchAudio.testStartNeverStartsMotors_RM10 | Auto (à confirmer) + Mac ; appareil | ⏳ |
| 6.5.6 | Fenêtre inactive sur Mac | P1 | SF-81 | via exigence : ScratchUI.testBackgroundSuspendsAndForegroundResumes_SF81, ScratchUI.testBackgroundSavesPendingPreferencesBeforeSuspending_SF81, ScratchAudio.testSuspendedHostOnlyStopsMotors_SF81 | Auto (à confirmer) + Mac | ⏳ |
| 6.5.7 | Mettre le Mac en veille | P1 | — | ScratchAudio.testSleepStopsMotorsAndWakeRestartsOutput | Auto | ⏳ |
| 6.5.8 | Brancher une interface audio USB | P1 | — | ScratchAudio.testOutputNameMapping, testMacConfigurationChange_D04 ; essai matériel (PO-08) | Mac matériel | ⏳ |
| 6.5.9 | Perdre le périphérique audio | P1 | — | ScratchAudio.testHeadphonesUnpluggedStopsBeforeTheSpeakerPlays_D04 | Auto | ⏳ |
| 6.5.10 | Débrancher le casque (iPhone/iPad) | P1 | — | ScratchAudio.testHeadphonesUnpluggedStopsBeforeTheSpeakerPlays_D04 ; hôte (#113) | Appareil | ⏳ |
| 6.5.11 | Changer de périphérique de sortie sur Mac | P1 | SF-80 | via exigence : ScratchAudio.testMonoIsDuplicatedAtEqualLevel_SF80, ScratchAudio.testSurroundIsDownmixedWithoutClipping_SF80, ScratchAudio.testSurroundChannelsAreIdentifiedByTheFileLayout_SF80 | Auto (à confirmer) + Mac | ⏳ |
| 6.5.12 | Aucune sortie audio disponible | P1 | SF-82 | via exigence : ScratchUI.testOutputBadgeLabels_SF16_SF82, ScratchUI.testOutputStatusFollowsHostAndWakesDisplay_SF82, ScratchAudio.testUnavailableOutputRetries_SF82 | Auto (à confirmer) + Mac | ⏳ |
| 6.5.13 | Restaurer les préférences | P1 | SF-17 | ScratchUI.testLaunchAppliesPreferencesWithoutPlayback_RM10, ScratchLibrary.testRoundTrip_SF17 | Auto | ⏳ |

### 6.6 Pitch et CUE

| # | Scénario | Prio | Exigences | Preuve prévue | Mode | Résultat |
|---|---|---|---|---|---|---|
| 6.6.1 | Modifier le pitch | P1 | SF-11 | ScratchCore.testPitchTable_SF11_RM50 | Auto | ⏳ |
| 6.6.2 | Remettre le pitch à zéro | P1 | SF-11 | ScratchUI.testPitchDoubleTapAndZeroButtonReset_6_6, ScratchCore.testSpeedChangeWhileSpinningIsContinuous_SF11 | Auto | ⏳ |
| 6.6.3 | Mémoriser un point CUE | P1 | SF-13, SF-69 | via exigence : ScratchUI.testCueButtonsSendCommandsAndAreDisabledWhenEmpty_SF13, ScratchCore.testJumpCrossfadeWithin5ms_SF13_SF71, ScratchCore.testCueAndSeek_SF13_SF71 | Auto (à confirmer) + Mac | ⏳ |
| 6.6.4 | Revenir au point CUE | P1 | SF-13 | via exigence : ScratchUI.testCueButtonsSendCommandsAndAreDisabledWhenEmpty_SF13, ScratchCore.testJumpCrossfadeWithin5ms_SF13_SF71, ScratchCore.testCueAndSeek_SF13_SF71 | Auto (à confirmer) + Mac | ⏳ |
| 6.6.5 | Rappeler CUE sans point enregistré | P1 | SF-13 | via exigence : ScratchUI.testCueButtonsSendCommandsAndAreDisabledWhenEmpty_SF13, ScratchCore.testJumpCrossfadeWithin5ms_SF13_SF71, ScratchCore.testCueAndSeek_SF13_SF71 | Auto (à confirmer) + Mac ; appareil | ⏳ |
| 6.6.6 | Définir un CUE pendant que je retiens le disque | P1 | SF-13 | via exigence : ScratchUI.testCueButtonsSendCommandsAndAreDisabledWhenEmpty_SF13, ScratchCore.testJumpCrossfadeWithin5ms_SF13_SF71, ScratchCore.testCueAndSeek_SF13_SF71 | Auto (à confirmer) + Mac | ⏳ |
| 6.6.7 | Rappeler le CUE pendant que je retiens le disque | P1 | SF-13 | ScratchCore.testRecallCueWhileHeldReanchorsGesture_IC09 | Auto ; appareil | ⏳ |
| 6.6.8 | Le CUE est propre à chaque son | P1 | SF-13, SF-64 | via exigence : ScratchUI.testCueButtonsSendCommandsAndAreDisabledWhenEmpty_SF13, ScratchCore.testJumpCrossfadeWithin5ms_SF13_SF71, ScratchCore.testCueAndSeek_SF13_SF71 | Auto (à confirmer) + Mac | ⏳ |

### 6.7 Résistance et inertie tactile réglables

| # | Scénario | Prio | Exigences | Preuve prévue | Mode | Résultat |
|---|---|---|---|---|---|---|
| 6.7.1 | Afficher le réglage sur l'interface principale | P1 | SF-21 | via exigence : ScratchUI.testResistanceDefaultAndStep_SF21 | Auto (à confirmer) + Mac | ⏳ |
| 6.7.2 | Réduire la résistance | P1 | SF-22 | ScratchCore.testHigherResistanceDampsAcceleration_SF22 | Auto | ⏳ |
| 6.7.3 | Augmenter la résistance | P1 | SF-22, SF-23 | ScratchCore.testHigherResistanceDampsAcceleration_SF22 | Auto | ⏳ |
| 6.7.4 | Conserver la possibilité d'arrêter le disque | P1 | RM-12 | via exigence : ScratchCore.testFingerStopConvergesToFinalAngleWithZeroVelocity_RM12, ScratchCore.testFixedFingerStopsDisc_RM12, ScratchCore.testReverseAtHighResistance_RM12 | Auto (à confirmer) + Mac | ⏳ |
| 6.7.5 | Scratcher en sens inverse avec une résistance élevée | P1 | RM-12, SF-23 | ScratchCore.testReverseAtHighResistance_RM12 | Auto | ⏳ |
| 6.7.6 | Modifier la résistance pendant le scratch | P1 | RM-13, SF-21, SF-23 | ScratchCore.testResistanceChangeWhileHeldIsContinuous_SF23, ScratchCore.testAbruptResistanceChangeIsSmoothed_SF23 | Auto | ⏳ |
| 6.7.7 | Ne pas modifier la vitesse nominale | P1 | RM-11 | ScratchCore.testResistanceDoesNotAffectMotorOrCatchUp_RM11_RM54 | Auto | ⏳ |
| 6.7.8 | La résistance ne ralentit pas le rattrapage | P1 | RM-54, SF-68 | via exigence : ScratchCore.testResistanceDoesNotAffectMotorOrCatchUp_RM11_RM54, ScratchCore.testStartReachesTargetInStartDuration_SF04_SF68, ScratchCore.testMotorDurationsAreClamped_SF68 | Auto (à confirmer) + Mac | ⏳ |
| 6.7.9 | Restaurer le réglage mémorisé | P1 | SF-17, SF-24 | via exigence : ScratchLibrary.testRoundTripThroughUserDefaults_SF17_SF24, ScratchLibrary.testDefaultsMatchSpec_SF17, ScratchLibrary.testRoundTrip_SF17 | Auto (à confirmer) + Mac | ⏳ |

### 6.8 Double platine

| # | Scénario | Prio | Exigences | Preuve prévue | Mode | Résultat |
|---|---|---|---|---|---|---|
| 6.8.1 | Les platines sont indépendantes | P0 | RM-51, SF-64 | via exigence : ScratchCore.testDecksAreIndependent_RM51, ScratchCore.testDeckBIsBitIdenticalWhetherOrNotAIsScratched_RM51 | Auto (à confirmer) + Mac | ⏳ |
| 6.8.2 | Scratcher A pendant que B joue | P0 | RM-51, SF-64 | ScratchCore.testDeckBIsBitIdenticalWhetherOrNotAIsScratched_RM51 | Auto | ⏳ |
| 6.8.3 | Charger le même son sur les deux platines | P0 | RM-57, SF-64 | via exigence : ScratchUI.testSameClipIsAnalyzedOnce_RM57, ScratchUI.testImportLoadsOnOriginDeckOnly_SF02_RM57, ScratchCore.testSameClipOnBothDecks_RM57 | Auto (à confirmer) + Mac | ⏳ |
| 6.8.4 | Scratcher les deux disques en même temps sur iPad | P0 | — | — (multitouch réel) | Appareil | ⏳ |
| 6.8.5 | Trois contacts simultanés | P0 | — | — (SF-19, D-05) | Appareil | ⏳ |
| 6.8.6 | Trois contacts simultanés sur iPhone en portrait | P0 | — | — (SF-19, D-05) | Appareil | ⏳ |
| 6.8.7 | Passer d'une platine à l'autre sur iPhone en portrait | P0 | RM-51, SF-64 | via exigence : ScratchCore.testDecksAreIndependent_RM51, ScratchCore.testDeckBIsBitIdenticalWhetherOrNotAIsScratched_RM51 | Auto (à confirmer) + Mac ; appareil | ⏳ |
| 6.8.8 | Pas de saturation à la somme des deux voies | P0 | SF-65 | ScratchCore.testTwoFullScaleSinesAreLimited_6_8, ScratchCore.testEngineSumOfTwoFullScaleDecksIsLimited_6_8 | Auto | ⏳ |

### 6.9 Feutrine, couple moteur et relâchement

| # | Scénario | Prio | Exigences | Preuve prévue | Mode | Résultat |
|---|---|---|---|---|---|---|
| 6.9.1 | Le plateau tourne sous le disque retenu | P0 | RM-53, SF-06 | ScratchUI.testPlatterKeepsSpinningUnderHeldDisc_6_9, ScratchCore.testPlatterIgnoresHold_RM53 | Auto | ⏳ |
| 6.9.2 | Rattrapage réglable | P0 | SF-10 | ScratchCore.testReleaseAttackIsNotSoftened_6_3 | Auto | ⏳ |
| 6.9.3 | Rattrapage plus lent | P0 | SF-10 | ScratchCore.testCatchUpReaches95PercentInSlipmatTime_SF10_SF68 | Auto | ⏳ |
| 6.9.4 | Démarrage court | P0 | SF-04 | ScratchCore.testStartReachesTargetInStartDuration_SF04_SF68 | Auto | ⏳ |

### 6.10 Courbe du crossfader et hamster

| # | Scénario | Prio | Exigences | Preuve prévue | Mode | Résultat |
|---|---|---|---|---|---|---|
| 6.10.1 | Gain des voies selon la courbe | P1 | RM-52, SF-66 | ScratchCore.testCurveTable_6_10 | Auto | ⏳ |
| 6.10.2 | Activer le hamster | P1 | RM-52, SF-67 | ScratchCore.testHamsterSwapsSidesWithoutClick_SF67 | Auto | ⏳ |
| 6.10.3 | Butées au clavier avec le hamster (Mac) | P1 | — | ScratchUI.testShiftArrowsAreLeftCentreRight_WithHamster_D09 | Auto | ⏳ |
| 6.10.4 | Conserver les réglages de crossfader | P1 | SF-17, SF-67 | via exigence : ScratchLibrary.testRoundTripThroughUserDefaults_SF17_SF24, ScratchLibrary.testDefaultsMatchSpec_SF17, ScratchLibrary.testRoundTrip_SF17 | Auto (à confirmer) + Mac | ⏳ |

### 6.11 Repère visuel, forme d'onde et needle drop

| # | Scénario | Prio | Exigences | Preuve prévue | Mode | Résultat |
|---|---|---|---|---|---|---|
| 6.11.1 | Le repère suit le disque | P1 | SF-69 | via exigence : ScratchUI.testJumpsRealignStickerAndLoadResetsDeck_SF03_SF69, ScratchCore.testStickerIsUnderThePlayheadAtCueAfterJumps_SF69_IC09, ScratchCore.testStickerUnderPlayheadAtCue_SF69_IC09 | Auto (à confirmer) + Mac | ⏳ |
| 6.11.2 | La forme d'onde suit le scratch | P1 | RM-13 | ScratchUI.testZoomWindowFollowsPlayhead_SF70 ; fluidité 120 Hz | Auto + Mac | ⏳ |
| 6.11.3 | Positionner la tête sur l'aperçu (needle drop) | P1 | SF-71 | via exigence : ScratchUI.testNeedleDropUsesDurationAndIsIgnoredWhileHeld_SF71, ScratchUI.testNeedleDropOnReleaseAtSeconds_SF71_D33, ScratchUI.testNeedleDropIgnoredWhileHeld_SF71 | Auto (à confirmer) + Mac | ⏳ |
| 6.11.4 | Needle drop ignoré pendant que je retiens le disque | P1 | SF-71 | ScratchUI.testNeedleDropIgnoredWhileHeld_SF71, ScratchCore.testSeekIgnoredWhileHeldAndSmoothed_SF71 | Auto | ⏳ |
| 6.11.5 | Annuler un needle drop | P1 | — | ScratchUI.testNeedleDropCancelledWhenLeavingOverview_D33 | Auto | ⏳ |
| 6.11.6 | Le repère reste aligné après un saut de position | P1 | — | ScratchCore.testStickerUnderPlayheadAtCue_SF69_IC09 | Auto | ⏳ |

### 6.12 Bornes, amorce et sillon fermé

| # | Scénario | Prio | Exigences | Preuve prévue | Mode | Résultat |
|---|---|---|---|---|---|---|
| 6.12.1 | Reculer dans l'amorce | P1 | RM-04, RM-50, SF-72 | ScratchCore.testLeadInStopWithImmediateReturn_RM55, ScratchCore.testLeadInStopAndAttack_RM55_6_12 | Auto | ⏳ |
| 6.12.2 | Dépasser la borne de l'amorce en reculant | P1 | RM-09, RM-55, SF-72 | ScratchCore.testLeadInStopAndAttack_RM55_6_12 | Auto | ⏳ |
| 6.12.3 | Atteindre la fin du son moteur actif (sillon fermé) | P1 | RM-55 | ScratchCore.testClosedGrooveEndsWithoutClickAndReturnsImmediately_RM55_6_12 | Auto | ⏳ |
| 6.12.4 | Revenir dans le son depuis le sillon fermé | P1 | RM-55 | ScratchCore.testEndStopWithImmediateReturn_RM55 | Auto | ⏳ |
| 6.12.5 | Son très court | P1 | RM-09 | ScratchCore.testVeryShortSoundScratchedAcrossBothBounds_6_12 | Auto | ⏳ |

### 6.13 Bibliothèque minimale et glisser-déposer

| # | Scénario | Prio | Exigences | Preuve prévue | Mode | Résultat |
|---|---|---|---|---|---|---|
| 6.13.1 | Consulter la bibliothèque | P1 | SF-74, SF-76 | ScratchUI.testListOrderAndRowTexts_SF74 | Auto | ⏳ |
| 6.13.2 | Charger un son de la bibliothèque sur la platine B | P1 | RM-57, SF-74 | ScratchUI.testLoadOnBGoesThroughLoadingFlow_6_13 | Auto | ⏳ |
| 6.13.3 | Supprimer un son non chargé | P1 | RM-49, SF-74 | ScratchUI.testDeleteUnloadedSoundAndFailure_RM49, ScratchLibrary.testDeleteRemovesCopyThenEntry_RM49 | Auto | ⏳ |
| 6.13.4 | Supprimer un son chargé sur une platine | P1 | RM-49, SF-74 | ScratchUI.testDeleteLoadedSoundUnloadsThenDeletes_RM49 | Auto | ⏳ |
| 6.13.5 | Le son de démonstration ne peut pas être supprimé | P1 | SF-74, SF-76 | ScratchUI.testDemoHasNoDeleteAction_6_13, ScratchLibrary.testDemoEntryIsFirstUndeletableWithoutFile_SF74 | Auto | ⏳ |
| 6.13.6 | Retrouver la bibliothèque après relancement | P1 | RM-58, SF-74 | ScratchLibrary.testLibraryPersistsAcrossInstances_6_13 | Auto | ⏳ |
| 6.13.7 | Déposer un fichier sur une platine | P1 | RM-47, SF-15 | via exigence : ScratchLibrary.testImportCopiesHashesAndIndexes_SF02_RM47, ScratchUI.testReplacementRules_SF15_D40, ScratchCore.testSnapshotActivityFlag_SF15 | Auto (à confirmer) + Mac | ⏳ |
| 6.13.8 | Déposer un fichier non audio | P1 | — | ScratchUI.testRejectsNonAudio_6_13 | Auto | ⏳ |
| 6.13.9 | Déposer plusieurs fichiers à la fois | P1 | — | ScratchUI.testRejectsMultipleFiles_D27 | Auto ; appareil | ⏳ |
| 6.13.10 | Importer deux fichiers portant le même nom | P1 | — | ScratchLibrary.testHomonymGetsUnderscoreSuffix_D12 | Auto ; appareil | ⏳ |
| 6.13.11 | Copie supprimée en dehors de l'application | P1 | — | ScratchUI.testLaunchReconcileShowsBanner_D11, ScratchLibrary.testReconcileRemovesAndReturnsMissingOrResizedCopies_RM48_D11 | Auto | ⏳ |
| 6.13.12 | Charger un son dont la copie a disparu | P1 | — | ScratchUI.testMissingCopyOnLoadShowsSonIntrouvable_D11, ScratchUI.testMissingCopyShowsAlertAndRemovesRow_D11, ScratchLibrary.testURLForMissingCopyRemovesEntryAndThrowsNotFound_D11 | Auto | ⏳ |

### 6.14 Commandes Mac

| # | Scénario | Prio | Exigences | Preuve prévue | Mode | Résultat |
|---|---|---|---|---|---|---|
| 6.14.1 | Retenir et scratcher à la souris | P0 | RM-53, RM-59, SF-06, SF-07, SF-08, SF-10 | via exigence : ScratchCore.testPlatterIgnoresHold_RM53, ScratchCore.testGrabbingSpinningDiscHasNoPositionJump_SF06, ScratchCore.testCatchUpReaches95PercentInSlipmatTime_SF10_SF68 | Auto (à confirmer) + Mac | ⏳ |
| 6.14.2 | Scratcher au trackpad | P0 | — | ScratchCore.testScrollFormulaAndCenterFallback_SF79, ScratchUI.testScrollDeltasFollowTheFingers_D24, ScratchCore.testScrollReleaseAfter80msOnInjectedClock_SF79 | Auto + Mac | ⏳ |
| 6.14.3 | Couper le son au clavier pendant un scratch à la souris | P0 | RM-59 | ScratchUI.testMomentaryCutOpensOnDownClosesOnUpAndOnFocusLoss_6_14 | Auto | ⏳ |
| 6.14.4 | Piloter le transport au clavier | P0 | — | ScratchUI.testKeyCodesMapToActions_3_5, testShortcutsAreConsumedOnlyInTheActiveContext_6_14 | Auto + Mac | ⏳ |
| 6.14.5 | Déplacer le crossfader au clavier | P0 | — | ScratchUI.testThreeRightArrowsFromLeftStopGive15Percent_6_14 | Auto | ⏳ |
| 6.14.6 | Raccourcis inactifs pendant la saisie de texte | P0 | — | ScratchUI.testModifiersAndTextFocusDisableShortcuts_6_14 | Auto | ⏳ |
| 6.14.7 | Raccourcis sur un clavier AZERTY | P0 | — | ScratchUI.testAzertyUsesPhysicalPositions_D08, testHelpAndMenusShowActiveLayoutCharacters_D08 | Auto + Mac | ⏳ |
| 6.14.8 | Redimensionner la fenêtre pendant un scratch | P0 | — | — (6.14 : la saisie est gardée sur Mac) | Mac | ⏳ |

### 6.15 Formats et fréquences

| # | Scénario | Prio | Exigences | Preuve prévue | Mode | Résultat |
|---|---|---|---|---|---|---|
| 6.15.1 | Lire un son à la bonne hauteur quelle que soit sa fréquence | P1 | — | ScratchCore.testPitchIndependentOfClipSampleRate_SF80_6_15 | Auto | ⏳ |
| 6.15.2 | Lire un son mono | P1 | — | ScratchAudio.testMonoIsDuplicatedAtEqualLevel_SF80 | Auto | ⏳ |
| 6.15.3 | Lire un son multicanal | P1 | — | ScratchAudio.testSurroundIsDownmixedWithoutClipping_SF80 | Auto | ⏳ |

### 6.16 Accessibilité

| # | Scénario | Prio | Exigences | Preuve prévue | Mode | Résultat |
|---|---|---|---|---|---|---|
| 6.16.1 | Libellés VoiceOver | P1 | — | ScratchUI.testSpokenValuesForEveryControl_SF83, ScratchUI.testListOrderAndRowTexts_SF74 | Auto ; appareil | ⏳ |
| 6.16.2 | Régler le pitch par les actions d'accessibilité | P1 | SF-11 | ScratchUI.testAccessibilityAdjustments_6_16, ScratchUI.testAdjustableStepsAndAnnouncements_6_16 | Auto | ⏳ |
| 6.16.3 | Navigation au clavier sur Mac | P1 | — | ScratchUI.testArrowsGoToFocusedControlThenCrossfaderAfterEscape_D07 ; ordre de tabulation (#106) | Mac | ⏳ |
| 6.16.4 | Flèches sur une commande qui a le focus (Mac) | P1 | — | ScratchUI.testArrowsGoToFocusedControlThenCrossfaderAfterEscape_D07 | Auto | ⏳ |

<!-- 128 scénarios -->

## 7. Anomalies

| Issue | Scénario ou critère | Gravité | État |
|---|---|---|---|
| — | | | |

## 8. Gate

À la fin de l'exécution : `docs/qa/gates/6.3-recette-v1.yml` (CA 7), avec les réserves (appareil, latence et mémoire selon les mesures) et les issues de suivi.
