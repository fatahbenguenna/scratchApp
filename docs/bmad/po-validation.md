# ScratchApp — Validation PO

- **Auteur :** 📝 Sarah, Product Owner BMAD
- **Date :** 14 novembre 2026
- **Issue :** #7
- **Artefacts validés :** spécifications v2.0 et [revue v1.9 → v2.0](../specs/REVUE_v1.9_vers_v2.0.md) ; [brief](project-brief.md) et [matrice de traçabilité](traceability.md) (📊 Mary) ; [PRD](prd.md) v1.0 (📋 John) ; [spécification UX](front-end-spec.md) v1.0 (🎨 Sally) ; [architecture](architecture.md) v1.1 et contrats `Sources/ScratchCore/Contracts/` (🏗️ Winston).
- **Livrables :** ce document ; les [spécifications v2.1](../specs/scratchapp_specifications_v2_1.md), qui font foi (la v2.0 est archivée dans `docs/specs/archive/`) ; corrections ciblées du PRD (v1.1), de la spec UX (v1.1), de l'architecture (v1.2) et de [`CONTRIBUTING.md`](../../CONTRIBUTING.md).
- **Destinataire suivant :** 🏃 Bob (découpage en stories), qui reprend le PRD v1.1 et la section 5 de ce document.

## 1. Verdict

**Prêt pour le développement**, avec quatre réserves. Aucune ne bloque le découpage en stories ni la vague 1.

| # | Réserve | Conséquence | Décisions |
|---|---|---|---|
| R1 | La CI ne construit que pour le simulateur iOS : les scénarios qui exigent un iPhone ou un iPad physique (trois contacts, latence tactile, interruptions, casque, dépôt depuis Fichiers) sont recettés hors de cet environnement. | Gate de recette CONCERNS tant que ces scénarios ne sont pas recettés ; la recette macOS est bloquante. | D-23 |
| R2 | L'objectif de 20 ms sur écran 120 Hz est serré : le rejeu du doigt ajoute environ 13 ms, le tampon 5,3 ms (architecture §6.4). | Mesure dès les stories 2.1 et 4.3 ; un dépassement donne une gate CONCERNS et une issue de calibrage. | D-15, D-16 |
| R3 | Plusieurs points ne se tranchent que sur matériel : mémoire avec deux sons de 10 min (PO-16), MPC Sample et Logic Pro (PO-08), calibrage de la résistance (PO-15). | Non bloquant ; résultats consignés en recette (6.3). | D-21, D-44, D-46 |
| R4 | Le contrat `LibraryStoring` ne permet pas encore de signaler à l'interface les entrées retirées par la réconciliation au lancement (D-11). | Ajout dans la story 3.1, avec l'accord de Winston (propriétaire des contrats). | D-11 |

**En chiffres.** 47 décisions (D-01 à D-47). Elles couvrent les 12 incohérences et les 3 questions du brief, les 14 points du PRD, les 25 questions et les 3 écarts de la spec UX, ainsi que E14, C1 à C6, ADR-05 et ADR-09 de l'architecture et les 8 points ouverts restants de la spec. La spec v2.1 n'ajoute ni ne renumérote aucun identifiant ; elle ajoute 11 scénarios Gherkin. La V1 compte 128 scénarios : 61 P0 et 67 P1, dont 3 marqués `@P1` dans des features [P0]. Les 72 exigences V1 restent rattachées à au moins une story (PRD 9.2, vérifié). Les recommandations de l'orchestrateur sont toutes adoptées. Les seules nuances, argumentées, portent sur D-02 (écart avec le PRD) et D-15 (définition de la mesure).

## 2. Checklist PO BMAD (« PO master checklist »)

Projet greenfield avec interface. La section des risques propres au brownfield est remplacée par une revue des risques du projet (2.7).

| # | Section | Statut | Points clés |
|---|---|---|---|
| 2.1 | Mise en place du projet | PASS | Squelette, CI et contrats fusionnés ; la vague 1 ne dépend que de 0.2. |
| 2.2 | Infrastructure et déploiement (CI) | PARTIAL | CI complète sur chaque PR ; aucun build signé ni distribution sur appareil (R1). |
| 2.3 | Dépendances externes | PASS | swift-atomics seulement, aucun service en ligne, démo générée. |
| 2.4 | Interface et expérience | PASS | Spec UX complète ; 25 questions et 3 écarts tranchés ; 3 incohérences UX corrigées. |
| 2.5 | Responsabilités | PASS | Un propriétaire par dossier ; actions humaines listées (section 6). |
| 2.6 | Séquencement des fonctionnalités | PASS | Graphe acyclique, contrats d'abord, P0 indépendant du P1 ; chemin critique porté par James. |
| 2.7 | Risques | PASS | Risques élevés traités ; risque résiduel accepté (R1, R2). |
| 2.8 | Périmètre MVP | PASS | P0 = app jouable sur macOS ; priorités en conflit tranchées (D-01, D-02). |
| 2.9 | Documentation et passation | PASS | Spec v2.1, PRD v1.1, UX v1.1, architecture v1.2 ; matrice à compléter par Quinn. |
| 2.10 | Après-MVP | PASS | Options P2 documentées, identifiants et formats prêts. |

### 2.1 Mise en place du projet — PASS

| Critère | Statut | Remarques |
|---|---|---|
| Squelette et structure du dépôt | PASS | Sprint 0 fusionné (#1) : `Package.swift` à quatre modules, `project.yml` (XcodeGen), apps iOS et macOS, `scripts/linux-test.sh`. |
| Environnement de développement documenté | PASS | README (Mac, Linux avec Docker), `CONTRIBUTING.md`, modèle de PR. |
| Contrats avant les stories | PASS | Story 0.2 fusionnée (#11) : `Contracts/`, squelettes silencieux compilables, doubles de test (`RecordingEngine`). |
| Dépendances de base | PASS | swift-atomics, seule dépendance ; toute nouvelle dépendance passe par une ADR. |
| Première vague exécutable | PASS | 1.1, 1.2, 3.1, 3.3 et 4.1 ne dépendent que de 0.2. |

### 2.2 Infrastructure et déploiement (CI) — PARTIAL

| Critère | Statut | Remarques |
|---|---|---|
| CI sur chaque PR de code | PASS | Linux (`swift test` sur ScratchCore et ScratchLibrary) et macOS 15 (tests, builds macOS et iOS, self-test, lancement, capture d'écran). Les PR de documentation n'exécutent pas la CI. |
| Self-test sans périphérique audio | PASS | Rendu manuel hors ligne (R-05 du brief, R-12 de l'architecture) ; horloge de secours pour l'app lancée sur le runner (D-35). |
| Environnements et données de test | PASS | Doubles, dossiers temporaires, fichiers générés à l'exécution ; pas de tests d'interface en V1 (recette). |
| Contrôle « aucune API réseau » | PASS | Story 6.2, critère 6 (NFR7). |
| Déploiement sur appareil et distribution | PARTIAL | Aucun build signé ni TestFlight dans cet environnement : la recette iOS sur appareil est une action humaine (R1, D-23). Pas de publication sur l'App Store en V1. |

### 2.3 Dépendances externes et intégrations — PASS

| Critère | Statut | Remarques |
|---|---|---|
| Bibliothèques tierces | PASS | swift-atomics ; SHA-256 en Swift pur (D-43) ; ni CryptoKit ni SDK tiers. |
| Services externes | PASS | Aucun : fonctionnement hors ligne, aucune donnée envoyée (SF-20, NFR6, NFR7). |
| API du système | PASS | AVFoundation, AVAudioSession, UIKit et AppKit, confinés aux modules Apple ; décodeurs du système (H-01). |
| Contenus tiers | PASS | Son de démonstration généré, sans licence (D-20) ; court MP3 libre de droits pour les tests, licence notée (2.2, critère 8). |
| Matériel de recette | PASS, avec réserve | iPhone, iPad, interface USB et MPC Sample ne servent qu'à la recette (R1, R3). |

### 2.4 Interface et expérience (UI/UX) — PASS

| Critère | Statut | Remarques |
|---|---|---|
| Spécification UX complète | PASS | Dispositions par appareil, composants, gestes, états, textes exacts, style, animation, accessibilité. |
| Questions UX tranchées | PASS | Q1 à Q25 et les trois écarts avec le PRD (section 4). |
| Cohérence UX ↔ spec | PASS après correction | Trois incohérences corrigées dans la spec UX : durée de la démo (« 0:30 » → 8 s, D-20), disques immobiles sans sortie (→ vivants, D-35), message « Son introuvable » (→ retrait automatique, D-11). |
| Cohérence UX ↔ contrats | PASS | `stickerAngle`, `isActive`, `channelGains`, `peakLevel` avant le crossfader, `Origin.demo`. |
| Accessibilité | PASS | SF-83, UX §11, story 5.3 ; contraste chiffré (4,5:1). |

### 2.5 Responsabilités (utilisateur et agents) — PASS

| Critère | Statut | Remarques |
|---|---|---|
| Propriété du code | PASS | PRD 5.4 et architecture §10 : un propriétaire par fichier ; contrats sous la responsabilité de Winston. |
| Points de contact entre développeurs | PASS | Protocole d'intentions (4.1 → 6.1), suivi d'angle (1.2 → 4.3), commandes de menu (5.1 → 6.2, 3.4), scénario hors ligne (1.5 → 2.4). |
| Actions humaines identifiées | PASS | Section 6 : recette sur appareil, signature, matériel USB, calibrage avec un turntablist. |
| Gates et acceptation | PASS | Quinn : gate par PR et recette 6.3 ; PO : acceptation des CONCERNS (TEAM.md). |

### 2.6 Séquencement des fonctionnalités — PASS

| Critère | Statut | Remarques |
|---|---|---|
| Dépendances explicites et acycliques | PASS | Graphe du PRD 8.3 vérifié : aucun cycle ; chaque story ne dépend que de stories de vagues antérieures, ou de la même vague chez le même développeur. |
| Contrats avant implémentations | PASS | 0.2 fusionnée ; l'interface avance sur le faux moteur et l'AppModel sur des doubles. |
| P0 indépendant du P1 | PASS | Le jalon « V1 — P0 jouable » ne contient aucune story P1. Les critères P1 portés par des stories P0 font partie de leur DoD et sont recettés au P1 (D-19). |
| Chemin critique | PASS, à surveiller | 0.2 → 1.1, 1.3, 1.4 → 1.5 → 2.1 → 6.2 → 6.3, porté par James (R-11 du brief). |
| Interdépendances transverses | PASS | 3.4 après 6.1 et 5.1 ; 2.4 après 3.3 ; 5.2 après 6.1 : cohérent avec les vagues. |

### 2.7 Risques — PASS

| Critère | Statut | Remarques |
|---|---|---|
| Risques identifiés, notés et suivis | PASS | Brief R-01 à R-11 ; architecture R-01 à R-15, avec parades et responsables. |
| Risques élevés traités | PASS | Latence (D-15, mesure précoce), temps réel en Swift (§6.1 de l'architecture, test d'allocations en 1.5), multitouch (surfaces UIKit, R-08), mémoire (ADR-05, D-21). |
| Risque résiduel | Accepté | Latence à 120 Hz (R2) et recette sur appareil (R1). |

### 2.8 Périmètre MVP — PASS

| Critère | Statut | Remarques |
|---|---|---|
| Objectifs ↔ exigences ↔ stories | PASS | 72 exigences V1, toutes rattachées à au moins une story (PRD 9.2). |
| Priorités cohérentes | PASS après décision | Les huit priorités en conflit (⚠) de la matrice sont tranchées (D-01, D-02). |
| P0 = app jouable sur macOS | PASS | 18 stories au jalon « V1 — P0 jouable ». |
| Hors périmètre respecté | PASS | Aucune commande P2 dans l'interface V1 ; aucune décision n'ajoute de fonction (le multitâche iPad reste une recette « devrait », D-29). |

### 2.9 Documentation et passation — PASS

| Critère | Statut | Remarques |
|---|---|---|
| Spec de référence à jour | PASS | v2.1 publiée, v2.0 archivée, liens mis à jour (README, `docs/bmad/`, revue). |
| Stories prêtes pour Bob | PASS | PRD v1.1 : critères corrigés (section 5). |
| Notes techniques | PASS | Architecture §5 à §11 (contrats, fils, moteur, erreurs, persistance, tests, arborescence). |
| Conventions de code | PASS | `CONTRIBUTING.md` et NFR14 alignés (D-42). |
| Traçabilité | PASS, action | La matrice de Mary porte sur la v2.0 : les ⚠ sont tranchés ici et signalés en tête de matrice ; Quinn rattache les 11 nouveaux scénarios dans la recette (6.3). |

### 2.10 Après-MVP — PASS

| Critère | Statut | Remarques |
|---|---|---|
| Options P2 documentées | PASS | Spec §10, identifiants conservés. |
| Architecture extensible | PASS | UUID stable (renommage, pointeurs), `Origin.microphone` et `.mix` réservés, `Documents/Enregistrements/` prévu, touches prédites transportées par le contrat. |
| Points ouverts classés | PASS | PO-12 en P2 (D-45) ; PO-11 et PO-13 en P2 (D-47). |
| Idées écartées consignées | PASS | Avertissement Bluetooth (Q21) et thème clair (Q23) pour après la V1. |

## 3. Registre des décisions

Chaque décision est intégrée à la spec v2.1 aux endroits cités, signalée **[Décision v2.1, D-nn]**. « Spec » désigne la v2.1 ; « UX », `front-end-spec.md` ; « Archi », `architecture.md`. Les numéros de stories et de critères (CA) sont ceux du PRD.

| ID | Sujet | Source | Décision | Impact (documents, stories) |
|---|---|---|---|---|
| D-01 | Priorités dans les features [P0] et priorités en conflit de la matrice | IC-01, A11, Q-03 | Dans 6.1, tag `@P1` sur « Recharger un son déjà importé sans accéder à Drive » (écran Bibliothèque, SF-74) et « Importer un contenu déjà présent dans la bibliothèque » (SF-75). Dans 6.2, tag `@P1` sur « Régler les durées de démarrage et de freinage » (écran Réglages, D-18). Les refus de fichiers (incompatible, protégé, corrompu, trop long) et la démo restent P0. Priorités des ⚠ : SF-20 P0 (vérifié au P0 par le contrôle CI d'absence d'API réseau, 6.2, et par le rechargement depuis la copie, 3.2) ; SF-76 P0 (premier lancement et self-test) ; SF-80 P0 ; RM-58 P0 (format persistant de l'index dès le premier import) ; SF-74 P1 (index et persistance livrés au P0 par 3.1) ; SF-75 P1 (porté par 3.2, D-19). « Lancer le son depuis le repère » (6.3) reste P0 : il vérifie SF-10, et le repère, dessiné dès 4.1, est sur 0 s sans CUE. | Spec 6 (convention), 6.1, 6.2, 7 ; matrice (note en tête) ; PRD 3.2 CA4. |
| D-02 | Courbe, hamster et latence | IC-02, A12 | Courbe continue du crossfader (SF-66) : P0. Hamster (SF-67) : P1, livré par 1.4 et 4.2 comme critère P1 (D-19). Conception basse latence (tampon de 256 trames, touches regroupées, événements transmis sans attendre l'affichage) : P0 (2.1, 4.2, 4.3). Mesure de latence (SF-78) : P1. Absence de clic (RM-08) et qualité du rendu (SF-77) : P0. Écart avec A12, qui livrait le hamster au P0 : la recommandation de l'orchestrateur est retenue, car le hamster n'est pas nécessaire à l'app jouable. | PRD 1.4 CA2 et CA4, 4.2 CA2. Stories 1.4, 4.2. |
| D-03 | Temps de rattrapage et relâchement moteur arrêté | IC-03, A1 | Le temps de rattrapage T est la durée au bout de laquelle l'écart entre la vitesse du disque et celle du plateau est réduit à 5 % de sa valeur au relâchement, soit 95 % de la vitesse du plateau pour un disque relâché immobile. Réponse du premier ordre de constante τ = T/3 ; T = 0 : alignement immédiat. Moteur arrêté : décélération linéaire (friction constante), arrêt 150 ms au plus après le relâchement. Correction de 5.1 §2, qui parlait d'une constante de temps égale à T. | Spec SF-10, SF-68, 5.1, 6.3, 6.9, 7. PRD 1.1 CA6 et CA7. Contrats déjà conformes (`MotorTimings`, `TurntableConstants`). Story 1.1. |
| D-04 | Changements de sortie audio | IC-04, A2 | Mac : si la sortie par défaut change et que l'ancienne existe encore, la lecture continue sur la nouvelle sortie, moteurs inchangés ; si le périphérique utilisé disparaît, STOP. iOS : `oldDeviceUnavailable` → STOP avant tout son sur le haut-parleur ; tout autre changement de route ne change pas l'état des moteurs. Interruption, arrière-plan (iOS) et veille (Mac) → STOP. La reprise est toujours manuelle. | Spec 0.3, SF-16, RM-56, 6.5 (+1 scénario : veille), note de 10. PRD 2.3 CA3 et CA4. Archi §7.3 déjà conforme. Story 2.3. |
| D-05 | Trois contacts selon la disposition | IC-05, Q4 | iPad et iPhone en paysage : disque A, disque B et crossfader (ou fader de voie). iPhone en portrait : disque affiché, crossfader et fader de voie. Partout : un disque tenu n'empêche pas les commandes de platine d'un autre doigt. | Spec 1, SF-19, 6.8 (+1 scénario). PRD 4.3 CA1. Stories 4.3, 4.4. |
| D-06 | Gain d'une voie et coupure momentanée | IC-06 | Gain = fader de voie × (coupure momentanée ouverte ? 1 : gain du crossfader). Un fader à 0 garde la voie muette, même coupure ouverte ; une voie dont le gain de crossfader vaut déjà 1 n'est pas modifiée ; montée ≤ 1 ms. `F` agit sur la voie A et `J` sur la voie B, quel que soit le hamster. | Spec RM-52, 5.2. PRD 1.4 CA5. Contrat conforme (`momentaryCut`). Story 1.4. |
| D-07 | Flèches et focus clavier (Mac) | IC-07, Q7, A10 | Les flèches agissent sur la commande réglable qui a le focus clavier, sinon sur le crossfader. Échap retire le focus. Les lettres de performance restent actives, sauf pendant une saisie de texte. | Spec 3.5, SF-83, 6.16 (+1 scénario). PRD 5.3 CA3 (règle confirmée). Stories 5.1, 5.3. |
| D-08 | Raccourcis par position physique | IC-08, Q6, A10 | Raccourcis lus par position physique de touche (code de touche, disposition QWERTY de référence). L'aide et les menus affichent le caractère réel du clavier courant (AZERTY, QWERTY…). | Spec 3.5, 6.14 (+1 scénario AZERTY). PRD 5.1 CA1 et CA6. Archi §5.2 déjà conforme. Story 5.1. |
| D-09 | Butées du crossfader au clavier | Q5, écart UX/PRD 5.1-1 | `⇧←` / `⇧→` placent le crossfader en butée gauche / droite **physiques**, `←` / `→` le déplacent dans leur sens, quel que soit le hamster. Même règle pour les actions VoiceOver. La proposition de Sally remplace « butée A / butée B » (spec v2.0, PRD). | Spec 3.5, 5.2, 6.14, 6.10 (+1 scénario). PRD 5.1 CA1. Story 5.1. |
| D-10 | Repère et recalage de l'angle du disque | IC-09, Q13, E14 | Formule de Winston : `stickerAngle = discAngle − 2π·cue/1,8`, avec `discAngle` recalé sur `2π·position/1,8` (correction d'au plus ±π) après chaque saut (CUE, needle drop, chargement) et à la sortie d'une butée. Disque tenu : aucun saut sous le doigt ni dans le son. La formule `… − 2π·(position − cue)/1,8` de l'orchestrateur est écartée : elle immobilise le repère en lecture normale. | Spec SF-69, RM-13, 5.4 (nouvelle précision), 6.11 (+1 scénario). Archi §14.1 E14 confirmé. Contrat conforme (`DeckSnapshot.stickerAngle`). Stories 1.1, 1.5, 4.1. |
| D-11 | Réconciliation de la bibliothèque | IC-10, R-10 du brief | Au lancement et avant chaque chargement, l'index est réconcilié avec les copies. Une entrée dont la copie a disparu ou a changé de taille est retirée, et l'utilisateur en est informé : bandeau au lancement, alerte au chargement. Un son déjà chargé continue d'être joué depuis la mémoire. Les fichiers absents de l'index sont ignorés en V1. Respecte RM-48. | Spec RM-48, SF-74, 5.3, 6.13 (+2 scénarios). UX 8.3 et 8.5. Archi §8. PRD 3.1 CA3, 6.1 CA5. **Contrat** : `LibraryStoring` doit exposer les entrées retirées (par exemple `reconcile() async -> [LibraryEntry]`), à ajouter en 3.1 avec l'accord de Winston (R4). Stories 3.1, 3.5, 6.1. |
| D-12 | Nommage des copies et titre affiché | IC-10, A3, Q25 ; Archi §8 | Dès la V1, la copie garde le nom d'origine ; en cas de collision, un suffixe `_2`, `_3`… est ajouté avant l'extension (`voix_funk_2.wav`), sans jamais écraser une copie (SF-60 et RM-43 appliqués dès la V1). Le titre affiché est le nom de la copie, ce qui distingue deux homonymes. Le suffixe `-2` de l'architecture devient `_2` (recommandation de l'orchestrateur). | Spec SF-02, 3.1, 5.3, 6.13 (+1 scénario), note de 10.5. Archi §8. UX 5.10. PRD 3.2 CA5. Story 3.2. |
| D-13 | Seuils chiffrés | IC-11 | Anti-repliement : une sinusoïde de 12 kHz lue à 3× (sortie à 48 kHz) ne produit que des composantes repliées inférieures d'au moins 40 dB au niveau du signal ; ce critère remplace celui du PRD (4 kHz à 8×). « Sans retard visible » (SF-70) : redessin à chaque image (60 i/s au moins, 120 i/s sur écran 120 Hz) depuis le dernier état du moteur, sans image perdue sur les appareils de référence. Saturation (6.8) : crête de sortie ≤ −0,1 dBFS ; témoin « limiteur actif » dès 1 dB de réduction ; « écrêtage » si la crête atteint 0 dBFS, cas qui ne doit pas se produire. Appareils de référence : D-14. | Spec 3.2, SF-65, SF-70, SF-77. PRD 1.3 CA4, 4.6 CA2. Archi §6.5. Stories 1.3, 1.4, 4.6. |
| D-14 | Appareils de référence | Q-01, A13, IC-11 | iPhone 13 ou plus récent, iPad avec puce M1 ou plus récente, Mac Apple Silicon. Ils servent à la recette des objectifs (latence, fluidité, mémoire) ; l'app reste installable sur tout appareil iOS 17 ou macOS 14. Écart avec A13 (iPad à puce A15) : recommandation de l'orchestrateur. | Spec SF-78. PRD NFR1, 6.3. Story 6.3. |
| D-15 | Latence geste→son | Q-02, A14, C2, PO-07, Q21 | Objectifs : 20 ms au plus sur écran 120 Hz, 30 ms au plus sur écran 60 Hz. Mesure de l'horodatage système de l'événement (toucher, clic, défilement) à la sortie du son, latence de sortie annoncée incluse : la latence propre de l'écran tactile, non mesurable par l'app, est exclue, ce qui rend l'objectif vérifiable. Sorties Bluetooth et AirPlay exclues, leur latence étant consignée telle quelle. Mesure en P1 (recette 6.3) ; un dépassement donne une gate CONCERNS et une issue de calibrage (rejeu, touches prédites, tampon de 128 trames), pas un refus. Pas d'avertissement Bluetooth en V1 (Q21). Le budget à 120 Hz étant serré (R2), James mesure dès 2.1 et 4.3. | Spec SF-78, 7, PO-07 clos. PRD NFR1, 6.3 CA3. Archi §6.4, R-03, §14.2. Stories 1.2, 2.1, 4.3, 6.3. |
| D-16 | Touches prédites | C1 | Transportées par le contrat ; employées seulement pour combler l'attente du rejeu entre deux livraisons de touches, sans jamais produire de dépassement aux inversions (SF-77). Emploi et calibrage décidés en 1.2. | Spec SF-78. PRD 1.2 CA6, 4.3 CA1. Stories 1.2, 4.3. |
| D-17 | Exigences par platine ou globales | IC-12 | SF-12, SF-16, SF-18, SF-19 et SF-20 sont globales ; SF-17 mêle réglages par platine et réglages globaux ; les durées moteur et le temps de rattrapage (SF-68) sont communs aux deux platines. Les autres exigences de SF-03 à SF-24 s'appliquent à chaque platine. | Spec 4 (introduction), SF-64, SF-68. Aucune story (contrats conformes). |
| D-18 | Réglages : moteur au P0, écran au P1 | A4 | Les réglages de durées et de rattrapage sont pris en charge par le moteur dès le P0 (1.1 CA2) ; l'écran Réglages est en P1 (3.4). Les scénarios de 6.9 sont vérifiés au P0 par les tests du cœur ; « Régler les durées… » (6.2) est tagué `@P1`. | Spec 3.3, 6.2. PRD inchangé. |
| D-19 | Critères P1 portés par des stories P0 | A5 | Accepté : résistance (1.1), CUE et needle drop (1.5), confirmation de remplacement (6.1), raccourcis de pitch et de CUE (5.1), et désormais hamster (1.4, 4.2 ; D-02) et dédoublonnage (3.2 ; D-01). Ces critères font partie du DoD de la story et sont recettés au P1. | PRD 1.4, 3.2, 4.2. Stories 1.1, 1.4, 1.5, 3.2, 4.2, 5.1, 6.1. |
| D-20 | Son de démonstration | A6, PO-14, Q19 | Généré par l'app, de façon déterministe : « stab » à 0 s puis voix synthétique « ahh », **8 s** (durée du contrat de Winston, dans la plage de 6 à 10 s du PRD), stéréo, 48 kHz, crête ≤ −1 dBFS. Titre « Son de démonstration », origine « Intégré ». Sans licence tierce : aucune mention de licence dans les Réglages (Q19). | Spec 1, SF-76, PO-14 clos. PRD 3.3 CA1. UX 5.19. Archi §14.3. Story 3.3. |
| D-21 | Mémoire et durée maximale | A7, PO-16, ADR-05 (E1) | Décodage complet en mémoire, Float32 stéréo, fréquence native plafonnée à 48 kHz (ADR-05 acceptée), budget de 650 Mo au plus avec deux sons de 10 min. La limite de 10 min est maintenue ; l'empreinte est mesurée en recette. En cas de dépassement sur un appareil de référence, gate CONCERNS, puis le PO réduit la limite par un amendement de SF-80, sans changer l'architecture. | Spec PO-16, 7. PRD 6.3 CA4 (inchangé). Stories 2.2, 6.3. |
| D-22 | Conversion de fréquence à la lecture | A8, ADR-05 | Rééchantillonnage à la volée dans la voix de lecture (incrément = vitesse × fréquence du clip / fréquence de sortie) ; aucun redécodage au changement de sortie. Conversion au décodage seulement au-delà de 48 kHz (D-21). | Spec SF-80. PRD 1.3 CA11, 2.2 CA4 (conformes). Stories 1.3, 2.2. |
| D-23 | Recette iOS et iPadOS sur appareil | A9 | La recette macOS est bloquante. Les scénarios qui exigent un appareil (trois contacts, latence tactile, interruptions, casque, dépôt depuis Fichiers, VoiceOver réel) sont listés dans la recette et exécutés par un humain sur iPhone et iPad de référence. Tant qu'ils ne le sont pas, la gate est CONCERNS, documentée, et le PO l'accepte pour le jalon. | Spec 7. PRD 6.3 CA6. Story 6.3. Section 6 (actions humaines). |
| D-24 | Trackpad et molette | A10, Q8 | Proposition de Sally : la surface du disque sous le pointeur suit les doigts (formule de UX §6.3) ; inertie ignorée ; un cran de molette = 15° ; relâchement 80 ms après le dernier événement ; un défilement commencé hors du disque ne le saisit pas. Calibrage sur appareil. | Spec SF-79. PRD 1.2 CA7. Stories 1.2, 4.3. |
| D-25 | Répétition des touches | A10 | Répétition automatique acceptée pour le pitch (`Z`, `X`, `,`, `.`) et pour `←` / `→` ; ignorée pour START/STOP, SET CUE, CUE, les coupures et les butées. | Spec 3.5. PRD 5.1 CA3. Story 5.1. |
| D-26 | VU-mètres | A10, Q15 | Niveau de la voie après le fader de voie, avant le crossfader (contrat `peakLevel` conforme). | Spec 3.2, SF-65. PRD 1.4 CA8 (confirmé). Stories 1.4, 4.2. |
| D-27 | Dépôt de plusieurs fichiers | A10, Q17, écart UX/PRD 5.2-4 | Refusé dès le survol (« Un seul fichier à la fois »). La proposition du PRD (charger le premier fichier) est écartée, car l'ordre d'une sélection Finder n'est pas visible. | Spec SF-73, 6.13 (+1 scénario). PRD 5.2 CA4. Story 5.2. |
| D-28 | Format de position | Q16, écart UX/PRD 4.1-4 | `mm:ss,d` avec la virgule décimale (« 00:12,3 ») ; « −00:01,2 » dans l'amorce ; « --:--,- » sans son. | Spec 3.1. PRD 4.1 CA4. Story 4.1. |
| D-29 | iPad portrait et multitâche | Q1, Q2 | Platines empilées quand la fenêtre est plus haute que large, côte à côte sinon. Multitâche pris en charge par la règle « largeur < 600 pt → une seule platine », en recette « devrait », non bloquante. | Spec 3.4. Story 4.4 (déjà dans UX 4.1, 4.4, 4.7). |
| D-30 | Courbe et hamster sur iPhone | Q3 | Panneau « Table » (popover) ouvert depuis la table de mixage, en portrait et en paysage. | Spec 3.2, 3.4. Stories 4.2, 4.4. |
| D-31 | Sens du fader de pitch | Q9 | « + » en haut : convention iOS, cohérente avec VoiceOver (balayer vers le haut augmente). | Spec 3.1. Story 4.5. |
| D-32 | Raccourcis clavier sur iPad | Q10 | Hors V1, même avec un clavier physique. | Spec 3.5. Aucune story. |
| D-33 | Needle drop | Q11 | Placement au relâchement ; tête fantôme et temps visé pendant l'appui ; annulation en sortant de l'aperçu ; geste ignoré pendant que le disque est tenu. Le scénario de 6.11 est réécrit avec une position en secondes, car l'aperçu couvre aussi l'amorce (UX §5.8). | Spec 3.1, SF-71, 6.11 (+1 scénario : annulation). PRD 4.6 CA4. Story 4.6. |
| D-34 | Menus Mac et coupures | Q12 | Menus Fichier, Platine, Table et Aide, avec les raccourcis à touche simple, désactivés pendant une saisie de texte ou un dialogue. `F` et `J`, qui se maintiennent, figurent seulement dans l'aide des raccourcis. | Spec 3.5, SF-79. PRD 5.1 CA5. Story 5.1. |
| D-35 | Sortie audio indisponible | Q14 | Horloge de secours (ADR-13) : disques, plateaux, VU-mètres et commandes restent vivants, en silence ; nouvel essai automatique ; aucun moteur ne démarre au retour d'une sortie. La proposition de Sally (disques immobiles) cède à l'alternative qu'elle mentionnait, déjà prévue par l'architecture. | Spec SF-82, 6.5. UX 7.3. PRD 2.1 CA6. Stories 2.1, 2.3. |
| D-36 | Origine affichée dans la bibliothèque | Q18, C5 | « Import » et « Intégré » (démo), pour les valeurs `.imported` et `.demo` du contrat. « Micro » viendra avec la banque P2. | Spec SF-74, 6.13. PRD 3.1 CA1. Stories 3.1, 3.5. |
| D-37 | Verrouillage automatique de l'écran (iOS) | Q20 | Désactivé tant qu'un moteur tourne ou qu'un disque est tenu. | Spec SF-81. PRD 6.2 CA4. Story 6.2. |
| D-38 | Fenêtre Mac | Q22 | Une seule fenêtre principale, sans « Nouvelle fenêtre » ; les 960 × 600 points désignent la zone de contenu ; fermer la fenêtre quitte l'app. | Spec 3.4, SF-81. Stories 4.1, 6.2. |
| D-39 | Thème | Q23 | Thème sombre imposé en V1 ; les jetons de couleur restent prêts pour un thème clair ultérieur. | Spec 3.4. Story 4.1. |
| D-40 | Platine vide en rotation ; « disque en mouvement » | Q24, C3 | Une platine vide ne demande jamais de confirmation, même plateau en rotation ; le chargement arrête son moteur (SF-03). « En mouvement » : vitesse de lecture supérieure à 0,001 en valeur absolue (`DeckSnapshot.isActive`). L'AppModel demande confirmation seulement si la platine porte un son et est active. | Spec SF-15. PRD 6.1 CA7. Story 6.1. |
| D-41 | Dates de l'index | C4 | Seule la date d'import (`importedAt`) en V1 ; d'autres dates viendront avec le P2. | Spec 5.3. Aucune story. |
| D-42 | Langue du code | C6 | Identifiants et noms de types en anglais ; commentaires de documentation (`///`) en français, comme les contrats ; commentaires techniques en ligne (`//`) en anglais ; documentation et libellés en français. | `CONTRIBUTING.md`, PRD NFR14, Archi §11. Toutes les stories. `AGENT_RULES.md` (hors dépôt) est à aligner par l'orchestrateur. |
| D-43 | SHA-256 | ADR-09 (E8) | ADR acceptée : implémentation en Swift pur, calculée en flux, testée avec les vecteurs officiels ; CryptoKit seulement par une nouvelle ADR, sur mesure. | Aucun changement (PRD 3.1 CA4 conforme). |
| D-44 | MPC Sample et Logic Pro | PO-08 | Ouvert, non bloquant : essai en recette si le matériel est disponible, sinon critère consigné « non testé, matériel indisponible ». La compatibilité USB générique (SF-16) reste exigée. | Spec PO-08. PRD 6.3 CA5 (conforme). Story 6.3. |
| D-45 | Rechargement de session | PO-12 | Clos pour la V1 : non retenu ; classé parmi les options P2 (10.7), à replanifier avec elles après la V1, sans jamais relancer l'audio. | Spec PO-12. Aucune story. |
| D-46 | Calibrage du modèle physique | PO-15 (et calibrage final de PO-03, PO-04) | Ouvert, non bloquant : constantes paramétrables (`TurntableConstants`, résistance de 2 à 35 ms par défaut), calibrées sur Mac en 1.1, puis validées sur appareil avec un turntablist ; un nouveau calibrage ne change pas les exigences (H-06). | Spec PO-15. Story 1.1 ; recette 6.3. |
| D-47 | Options P2 encore ouvertes | PO-11, PO-13 | Restent ouverts, en P2, sans effet sur la V1. | Aucun. |

## 4. Index des sources

| Source | Points | Décisions |
|---|---|---|
| Brief (Mary), incohérences | IC-01 · IC-02 · IC-03 · IC-04 · IC-05 · IC-06 · IC-07 · IC-08 · IC-09 · IC-10 · IC-11 · IC-12 | D-01 · D-02 · D-03 · D-04 · D-05 · D-06 · D-07 · D-08 · D-10 · D-11 et D-12 · D-13 et D-14 · D-17 |
| Brief (Mary), questions | Q-01 · Q-02 · Q-03 | D-14 · D-15 · ensemble du registre (D-01 pour les priorités) |
| PRD (John) | A1 · A2 · A3 · A4 · A5 · A6 · A7 · A8 · A9 · A10 · A11 · A12 · A13 · A14 | D-03 · D-04 · D-12 · D-18 · D-19 · D-20 · D-21 · D-22 · D-23 · D-07, D-08, D-24, D-25, D-26, D-27 · D-01 · D-02 · D-14 · D-15 |
| Spec UX (Sally), Q1 à Q13 | Q1 · Q2 · Q3 · Q4 · Q5 · Q6 · Q7 · Q8 · Q9 · Q10 · Q11 · Q12 · Q13 | D-29 · D-29 · D-30 · D-05 · D-09 · D-08 · D-07 · D-24 · D-31 · D-32 · D-33 · D-34 · D-10 |
| Spec UX (Sally), Q14 à Q25 | Q14 · Q15 · Q16 · Q17 · Q18 · Q19 · Q20 · Q21 · Q22 · Q23 · Q24 · Q25 | D-35 · D-26 · D-28 · D-27 · D-36 · D-20 · D-37 · D-15 · D-38 · D-39 · D-40 · D-12 |
| Spec UX (Sally), écarts avec le PRD | 4.1-4 (format de position) · 5.1-1 (butées) · 5.2-4 (dépôt multiple) | D-28 · D-09 · D-27 |
| Architecture (Winston) | E14 · C1 · C2 · C3 · C4 · C5 · C6 · ADR-05 (E1) · ADR-09 (E8) · §8 (suffixe `-2`) | D-10 · D-16 · D-15 · D-40 · D-41 · D-36 · D-42 · D-21 et D-22 · D-43 · D-12 |
| Spec v2.0, points ouverts | PO-07 · PO-08 · PO-11 · PO-12 · PO-13 · PO-14 · PO-15 · PO-16 | D-15 · D-44 · D-47 · D-45 · D-47 · D-20 · D-46 · D-21 |

## 5. Changements à reporter dans les stories (pour Bob)

Le PRD v1.1 intègre déjà ces corrections ; Bob reprend les critères tels quels et ajoute aux stories les scénarios cités.

| Story | Critères modifiés | Décisions |
|---|---|---|
| 1.1 | CA6 : définition définitive du rattrapage (écart réduit à 5 % en T, τ = T/3) ; CA7 : décélération linéaire | D-03 |
| 1.2 | CA6 : emploi limité des touches prédites ; CA7 : trackpad (surface qui suit les doigts, inertie ignorée, molette 15°) | D-16, D-24 |
| 1.3 | CA4 : anti-repliement mesuré sur 12 kHz lu à 3×, −40 dB | D-13 |
| 1.4 | CA2 et CA4 : hamster devenu critère P1 ; CA5 : formulation de la coupure momentanée ; CA8 : VU-mètre confirmé | D-02, D-06, D-26 |
| 1.5 | Aucun changement de critère ; citer le scénario 6.11 « Le repère reste aligné après un saut de position » | D-10 |
| 2.1 | CA6 : horloge de secours, disques vivants sans sortie | D-35 |
| 2.3 | CA3 et CA4 : règle des sorties ; citer le scénario 6.5 « Mettre le Mac en veille » | D-04 |
| 3.1 | CA1 : origine « Intégré » ; CA3 : réconciliation et entrées retirées signalées (**changement de contrat**, avec Winston) ; citer les scénarios 6.13 sur les copies disparues | D-36, D-11 |
| 3.2 | CA4 : dédoublonnage marqué critère P1 ; CA5 : suffixe `_2` et titre ; citer le scénario 6.13 « Importer deux fichiers portant le même nom » | D-01, D-12 |
| 3.3 | CA1 : durée fixée à 8 s | D-20 |
| 4.1 | CA4 : format `mm:ss,d` | D-28 |
| 4.2 | CA2 : hamster devenu critère P1 | D-02 |
| 4.3 | CA1 : combinaison de l'iPhone en portrait, touches prédites ; citer le scénario 6.8 « Trois contacts simultanés sur iPhone en portrait » | D-05, D-16 |
| 4.6 | CA2 : fluidité chiffrée ; CA4 : placement au relâchement et annulation ; citer le scénario 6.11 « Annuler un needle drop » | D-13, D-33 |
| 5.1 | CA1 : position physique et butées gauche et droite ; CA3 : répétition ; CA5 : menu Aide, `F` et `J` hors menus ; CA6 : caractère réel dans l'aide ; citer les scénarios 6.14 « Raccourcis sur un clavier AZERTY » et 6.10 « Butées au clavier avec le hamster (Mac) » | D-08, D-09, D-25, D-34 |
| 5.2 | CA4 : dépôt multiple refusé ; citer le scénario 6.13 « Déposer plusieurs fichiers à la fois » | D-27 |
| 5.3 | CA3 : règle des flèches confirmée ; citer le scénario 6.16 « Flèches sur une commande qui a le focus (Mac) » | D-07 |
| 6.1 | CA5 : copie introuvable, entrée retirée ; CA7 : platine vide sans confirmation | D-11, D-40 |
| 6.2 | CA4 : écran sans verrouillage automatique pendant le jeu | D-37 |
| 6.3 | CA3 : objectifs de latence et méthode ; CA6 : gate CONCERNS pour la recette sur appareil | D-15, D-23 |

Les autres stories (2.2, 2.4, 3.4, 3.5, 4.4, 4.5) ne changent pas de critères ; leurs sections de spec ou d'UX ont été précisées (D-20, D-29, D-30, D-31, D-36).

## 6. Actions humaines hors de cet environnement

- **Recette sur iPhone et iPad de référence** (D-23) : build signé (compte développeur Apple), trois contacts, latence tactile, interruptions, casque, dépôt depuis Fichiers, VoiceOver.
- **Essai sur matériel USB** (D-44) : MPC Sample ou autre interface USB, enregistrement dans Logic Pro.
- **Session de calibrage** avec un turntablist (D-46) : résistance, feutrine, durées moteur, trackpad.
- **Mesure physique de latence**, facultative : la mesure instrumentée de D-15 fait foi ; une mesure caméra ou micro peut la compléter.

## 7. Documents modifiés

| Document | Modification |
|---|---|
| `docs/specs/scratchapp_specifications_v2_1.md` | Créé à partir de la v2.0 : décisions intégrées, tags `@P1`, 11 scénarios, recette, points ouverts, journal. |
| `docs/specs/archive/scratchapp_specifications_v2_0.md` | Déplacé (`git mv`), avec un renvoi vers la v2.1 et un lien relatif corrigé. |
| `docs/bmad/prd.md` | v1.1 : critères des stories (section 5), NFR1, NFR14, statut, liens. |
| `docs/bmad/front-end-spec.md` | v1.1 : 5.10, 5.19, 7.3, 8.3, 8.5, 13.2, 14, liens. |
| `docs/bmad/architecture.md` | v1.2 : §6.4, §6.5, §8, §11, §13, §14, liens. |
| `docs/bmad/project-brief.md`, `docs/bmad/traceability.md` | Liens vers la v2.1 ; note sur les priorités tranchées. |
| `docs/specs/REVUE_v1.9_vers_v2.0.md`, `README.md` | Liens vers la v2.0 archivée et la v2.1. |
| `CONTRIBUTING.md` | Langue des commentaires (D-42). |
