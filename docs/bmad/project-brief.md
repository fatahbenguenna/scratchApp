# ScratchApp — Brief produit (Project Brief BMAD)

- **Auteur :** 📊 Mary, Analyst BMAD
- **Date :** 14 novembre 2026
- **Sources :** spécifications v2.0, analysées ici et désormais archivées ([`archive/scratchapp_specifications_v2_0.md`](../specs/archive/scratchapp_specifications_v2_0.md)), et [`REVUE_v1.9_vers_v2.0.md`](../specs/REVUE_v1.9_vers_v2.0.md). La spec qui fait foi est la [v2.1](../specs/scratchapp_specifications_v2_1.md), qui intègre les décisions du PO.
- **Artefact compagnon :** [`traceability.md`](traceability.md) : matrice des 72 exigences V1 → épopées → scénarios Gherkin → vérification.
- **Statut :** à valider par le PM (John) et le PO (Sarah). Aucune exigence nouvelle : les identifiants SF, RM, PO et E renvoient à la spec v2.0.
- **Renvois :** « §n » et « 6.n » désignent les sections de la spec v2.0 ; I-nn et E-nn, la revue v1.9 → v2.0 ; « section n », ce brief.

## 1. Résumé exécutif

ScratchApp reproduit une **double platine vinyle 33⅓ tours avec table de mixage** sur iPhone, iPad (iOS/iPadOS 17+) et Mac (macOS 14+), pour scratcher ses propres fichiers audio au doigt, ou à la souris, au trackpad et au clavier. Le scratch n'est pas un effet préenregistré : il est calculé en temps réel à partir du son chargé, selon la position et la vitesse de chaque disque (RM-04, RM-05, RM-50).

La V1 réunit les priorités **P0** (charger deux sons, faire tourner, scratcher et couper au crossfader sur les trois appareils) et **P1** (robustesse, périphériques, pitch et CUE, résistance, repère et forme d'onde, bibliothèque, accessibilité). Elle compte 72 exigences (44 SF, 28 RM ; 42 P0 et 30 P1), 117 scénarios Gherkin en 16 features (62 P0, 55 P1) et 18 critères de recette.

Le succès se joue sur trois points : une **latence geste→son ≤ 20 ms**, une **qualité audio sans clic** aux inversions et aux coupures, et une **sensation de platine réelle** (feutrine, cut-in ≤ 3 %, repère). Les risques majeurs sont techniques : temps réel en Swift, multitouch, mémoire, CI sans périphérique audio. Chacun a une parade (section 8). Douze incohérences ou ambiguïtés de la spec sont à arbitrer avant le découpage en stories (section 10).

## 2. Problème et solution

### 2.1 Problème

- Une installation de scratch, ce sont deux platines et une table de mixage : on scratche une phrase sur une platine pendant que l'autre joue la rythmique, et on rythme les coupures au crossfader (revue, E-01).
- La v1.9 ne permettait pas de scratcher « comme sur une double platine 33 tours » : une seule platine (I-05), pas de Mac (I-06), reprise au relâchement non bornée qui empêche le « release » (I-10), courbe de crossfader jamais définie (E-02), blocage strict à 0 s qui empêche d'attaquer le son (E-05), correspondance angle ↔ temps non quantifiée (I-11).
- Le geste est exigeant : huit inversions par seconde dans un « baby scratch », ouverture de voie sur 3 % de course. Une latence supérieure à 20 ms ou une marche de vitesse se sent au doigt et s'entend (E-06).
- Sur Mac, sans écran tactile, un seul pointeur ne peut pas tenir le disque et le crossfader en même temps (RM-59).

### 2.2 Solution

- **Deux platines indépendantes** A et B (SF-64, RM-51) et une **table de mixage** : faders de voie, crossfader à courbe réglable jusqu'à la coupure franche, hamster, VU-mètres, marge et limiteur doux (SF-65 à SF-67).
- **Modèle physique** calculé à la fréquence audio : plateau motorisé, feutrine avec rattrapage de 60 ms, résistance réglable, amorce de 2 s et sillon fermé ; un tour de disque = 1,8 s de son (SF-68, SF-72, RM-50, RM-55, §5.1).
- **Rendu de qualité** : interpolation au moins cubique, repliement atténué, vitesse bornée à ±16×, tampon ≤ 256 trames (SF-77, SF-78).
- **Repérage visuel** : repère sur l'étiquette, forme d'onde zoomée et aperçu, needle drop (SF-69 à SF-71).
- **Sons** : import par le sélecteur du système ou glisser-déposer, copie locale systématique, bibliothèque minimale avec dédoublonnage SHA-256, son de démonstration (SF-02, SF-73 à SF-76, RM-47 à RM-49, RM-58).
- **Commandes Mac** : clic-glisser, défilement au trackpad, coupures momentanées et crossfader au clavier, menus (SF-79, §3.5).
- **Robustesse** : interruptions, arrière-plan, changements de sortie, sortie indisponible, hors ligne, jamais de reprise sonore automatique (SF-16 à SF-18, SF-20, SF-81, SF-82, RM-10, RM-56).

## 3. Utilisateurs cibles

### 3.1 Persona 1 — DJ scratch débutant sur iPhone

- **Contexte :** découvre le scratch sans matériel, au casque ou au haut-parleur, souvent en portrait : une platine visible, sélecteur A/B, crossfader au pouce (§3.4).
- **Objectif :** essayer tout de suite, puis apprendre les gestes de base (baby scratch, release) sur ses propres sons.
- **Attentes clés :** aucune configuration (SF-01), son de démonstration (SF-76), réponse immédiate et sans clic (SF-77, SF-78), bornes prévisibles (SF-72, RM-55), aucune lecture surprise (RM-10, SF-17).
- **Vigilance :** casque Bluetooth (H-03), arrière-plan (SF-81), trois contacts impossibles en portrait (IC-05).

### 3.2 Persona 2 — Turntablist confirmé sur iPad

- **Contexte :** pratique sur de vraies platines ; utilise l'iPad en paysage (A à gauche, table au centre, B à droite) pour s'entraîner ou jouer en déplacement.
- **Objectif :** retrouver la sensation d'une vraie installation : coupures (transformer, chirp, flare, crab), release depuis le repère, deux disques et le crossfader en même temps.
- **Attentes clés :** cut-in ≤ 3 % et hamster (SF-66, SF-67), feutrine et rattrapage réglable (SF-68), repère et forme d'onde (SF-69, SF-70), résistance (SF-21 à SF-24), trois contacts (SF-19), latence ≤ 20 ms (SF-78), glisser-déposer depuis Fichiers (SF-73).
- **Vigilance :** il juge au doigt ; le calibrage sur appareil (PO-04, PO-15) et la qualité aux vitesses élevées (SF-77) décident de l'adoption.

### 3.3 Persona 3 — Producteur sur Mac avec interface USB et MPC

- **Contexte :** compose sur Mac, envoie le son vers une interface USB ou une MPC Sample reliée en USB, et enregistre ses scratchs dans sa station de travail (PO-08).
- **Objectif :** produire vite des phrases scratchées à partir de ses samples, à la souris et au clavier, sans contrôleur dédié.
- **Attentes clés :** disque à la souris et au trackpad, coupures momentanées F/J et crossfader au clavier (SF-79, RM-59), import Finder et glisser-déposer (SF-02, SF-73), bibliothèque (SF-74), sortie USB nommée et changement de périphérique à une autre fréquence (SF-16, SF-80), lecture fenêtre inactive (SF-81).
- **Vigilance :** clavier AZERTY (IC-08), flèches et navigation au clavier (IC-07), compatibilité MPC à tester sur matériel (PO-08). Le contrôleur MIDI (E-10) reste en P2.

## 4. Objectifs et indicateurs de succès

- **O-1 :** livrer la V1 (P0 + P1) sur iPhone, iPad et Mac à partir d'une base de code Swift unique.
- **O-2 :** offrir un scratch crédible pour un turntablist : réactivité, aucun artefact, feutrine et coupure franche.
- **O-3 :** garantir la robustesse : aucun plantage, aucune reprise sonore non demandée, aucune perte de son importé.
- **O-4 :** rendre la qualité vérifiable en continu : tests automatisés et CI Linux et macOS verte à chaque PR.

Types de mesure (UL, TM, ST, MA) : voir la section 1 de [`traceability.md`](traceability.md).

| ID | Indicateur | Cible | Source | Mesure |
|---|---|---|---|---|
| KPI-01 | Latence geste→son | ≤ 20 ms sur iPhone, iPad récents et Mac, mesurée et consignée | SF-78, §7 P1 | MA |
| KPI-02 | Tampon audio | ≤ 256 trames à 48 kHz (≈ 5,3 ms) quand le matériel le permet | SF-78 | TM, MA |
| KPI-03 | Clics aux inversions | Zéro clic sur le baby scratch (8 inversions/s, ¼ de tour) ; retour de position à ±10 ms | 6.3, SF-77, RM-08 | UL, MA |
| KPI-04 | Cut-in | Plein niveau en ≤ 3 % de course ; gains du tableau 6.10 à ±0,05 ; montée ≤ 1 ms | SF-66, RM-52 | UL |
| KPI-05 | Lissages | Hamster, needle drop et gains lissés sur ≤ 5 ms | SF-67, SF-71, RM-52 | UL |
| KPI-06 | Relâchement | Rattrapage 60 ms par défaut (0 à 300 ms) ; arrêt ≤ 150 ms moteur arrêté | SF-10, SF-68 | UL, MA |
| KPI-07 | Vitesses | 33⅓ et 45 RPM ; démarrage 0,7 s, freinage 1,0 s (0,1 à 5 s) ; pitch ±8 % par 0,1 % | SF-04, SF-05, SF-11, SF-68 | UL |
| KPI-08 | Simultanéité | 3 contacts indépendants (iPad) ; souris et clavier simultanés (Mac) | SF-19, SF-79 | MA |
| KPI-09 | Forme d'onde | ≥ 60 images/s pendant le scratch | SF-70 | MA |
| KPI-10 | Saturation | Aucun écrêtage numérique avec deux sons à 0 dBFS à plein niveau | SF-65, 6.8 | UL, ST |
| KPI-11 | CI | Linux (ScratchCore, ScratchLibrary) et macOS (tests, builds macOS et iOS, self-test, lancement) verts sur chaque PR de code | §7 P0 | CI |
| KPI-12 | Recette | 117 scénarios P0/P1 couverts par un test ou une recette manuelle ; 18/18 critères §7 cochés | §6, §7 | Toutes |
| KPI-13 | Robustesse | Zéro plantage dans les scénarios d'erreur et de cycle de vie (6.1, 6.5) | SF-82, §7 P1 | TM, MA |
| KPI-14 | Accessibilité | 100 % des commandes étiquetées pour VoiceOver ; contraste WCAG AA des libellés | SF-83 | TM, MA |
| KPI-15 | Temps réel | Aucune allocation ni verrou bloquant dans le fil de rendu (revue QA de chaque PR) | §5.1, modèle de PR | Revue, UL |

## 5. Périmètre MVP (V1 = P0 + P1)

Priorités déduites des features Gherkin et des critères de recette (règle et détail : `traceability.md`). ⚠ = priorité en conflit (section 10).

| Bloc | Contenu V1 | Exigences | Prio | Épopée |
|---|---|---|---|---|
| Ouverture | Platines et table affichées sans lecture ; import et démo proposés | SF-01, RM-01 | P0 | EP4, EP6 |
| Import et chargement | Sélecteur du système, copie locale atomique, erreurs ; état initial après chargement | SF-02, SF-03, RM-47, RM-48 | P0 | EP3, EP2 |
| Moteur | START/STOP progressifs, 33⅓ et 45 RPM, gravure virtuelle à 33⅓ | SF-04, SF-05, RM-02, RM-50 | P0 | EP1 |
| Scratch | Prise en main, avant/arrière, vitesse du geste, relâchement, gestes particuliers | SF-06 à SF-10, RM-03 à RM-08, RM-60, RM-61 | P0 | EP1, EP4 |
| Double platine | Platines indépendantes, même son possible sur A et B | SF-64, RM-51, RM-57 | P0 | EP1, EP6 |
| Table de mixage | Faders de voie, crossfader, courbe et cut-in ≤ 3 %, marge et limiteur, VU-mètres | SF-12, SF-65, SF-66, RM-52 | P0 | EP1, EP4 |
| Feutrine | Plateau sous le disque retenu ; rattrapage et durées réglables | SF-68, RM-53 | P0 | EP1 |
| Qualité audio | Interpolation ≥ cubique, anti-repliement, vitesse bornée à ±16× | SF-77 | P0 | EP1 |
| Multitouch et Mac | 3 contacts (iPhone/iPad) ; souris, trackpad, clavier et menus (Mac) | SF-19, SF-79, RM-59 | P0 | EP4, EP5 |
| Bibliothèque et démo | Liste, chargement A/B, suppression, dédoublonnage, démo, hors ligne | SF-20, SF-74 à SF-76, RM-58 (P0 ⚠) ; RM-49 (P1) | P0/P1 | EP3 |
| Formats | Mono, stéréo, multicanal ; conversion de fréquence ; 50 ms à 10 min | SF-80 (⚠) | P0 | EP2 |
| Pitch et CUE | Pitch ±8 % par 0,1 % ; SET CUE / CUE | SF-11, SF-13 | P1 | EP1, EP4 |
| Bornes | Amorce de 2 s, sillon fermé, jamais de lecture hors bornes | SF-14, SF-72, RM-09, RM-55 | P1 | EP1 |
| Résistance | Curseur 0–100 %, effet, continuité, mémorisation | SF-21 à SF-24, RM-11 à RM-13, RM-54 | P1 | EP1, EP4 |
| Hamster | Inversion du crossfader sans clic | SF-67 (⚠) | P1 | EP1 |
| Repérage | Repère, forme d'onde, needle drop | SF-69 à SF-71 | P1 | EP4, EP1 |
| Remplacement et dépôt | Confirmation si la platine est active ; glisser-déposer | SF-15, SF-73 | P1 | EP6, EP5 |
| Cycle de vie et sortie | Route active et USB, préférences, interruptions, arrière-plan, sortie indisponible | SF-16 à SF-18, SF-81, SF-82, RM-10, RM-56 | P1 | EP2, EP6, EP3 |
| Latence | Tampon ≤ 256 trames, geste→son ≤ 20 ms mesurée | SF-78 (⚠) | P1 | EP2, EP4 |
| Accessibilité | VoiceOver, actions d'accessibilité, clavier Mac, WCAG AA | SF-83 | P1 | EP5 |

**Hors périmètre V1.**

- **Options P2 documentées (§10 de la spec) :** reverse motorisé (SF-25 à SF-28), crépitement vinyle (SF-29 à SF-34), enregistrement du mix (SF-35 à SF-41), pointeurs (SF-42 à SF-50), micro et banque de sons complète avec renommage (SF-51 à SF-63), options 10.7 (MIDI E-10, pitch ±16/±50 % E-11, retour haptique, « power down », boucle en fin de son, rechargement de session).
- **Exclus (§1) :** synchronisation BPM, stems en temps réel, effets complexes, export et partage avancés, plugin Logic Pro, vinyle timecode (DVS), streaming, plus de deux platines.
- **Non retenus en V1 :** audio en arrière-plan sur iOS/iPadOS (SF-81), rechargement des sons au lancement (SF-17, PO-12), gain de déplacement tactile réglable (§5.1). Les contrôles de §3.6 ne sont pas requis pour la recette ; l'UUID stable (RM-58) prépare déjà le renommage et les pointeurs P2.

## 6. Contraintes techniques

- **Plateformes :** iOS 17+, iPadOS 17+, macOS 14 Sonoma+ ; fenêtre Mac d'au moins 960 × 600 points (§3.4) ; interface en français.
- **Langage et frameworks :** Swift, SwiftUI, AVAudioEngine ; décodeurs du système pour WAV, AIFF, MP3, M4A (AAC, ALAC) ; fichiers protégés refusés (SF-02).
- **Modules :** ScratchCore et ScratchLibrary testables sous Linux ; ScratchAudio, ScratchUI et App vérifiables seulement sur la CI macOS (runner macOS 15).
- **Temps réel :** tête de lecture et paramètres intégrés à la fréquence audio, dans le fil de rendu (§5.1, SF-77) ; ni allocation, ni verrou bloquant dans ce fil (modèle de PR).
- **Latence :** tampon ≤ 256 trames à 48 kHz si le matériel le permet ; touches regroupées et prédites (SF-78).
- **Sortie :** stéréo ; route active du système (iOS) ou périphérique par défaut (macOS), USB compris ; conversion vers la fréquence de la sortie (SF-16, SF-80).
- **Cycle de vie iOS :** session de catégorie « lecture » exclusive ; pas d'audio en arrière-plan : STOP et sortie coupée (PO-09, SF-81, RM-56).
- **Bac à sable :** copies dans `Documents/Banque de sons/`, index `Application Support/ScratchApp/library.json` à écriture atomique, préférences dans `UserDefaults` (§5.3) ; sur Mac, accès aux seuls fichiers choisis ou déposés ; jamais de signet ni de chemin externe (SF-02, RM-47).
- **Hors ligne :** aucune dépendance réseau (SF-20).
- **Sons :** 50 ms à 10 min, mono à multicanal réduit en stéréo (SF-80).

## 7. Hypothèses

- **H-01 :** les décodeurs du système suffisent pour tous les formats V1 ; aucun décodeur tiers.
- **H-02 :** chaque son est décodé et converti en mémoire avant lecture, car le fil de rendu ne peut pas lire le disque (§5.1, SF-80).
- **H-03 :** l'objectif de 20 ms (SF-78) vise les sorties intégrées, filaires et USB ; les sorties Bluetooth, dont la latence propre le dépasse, n'en relèvent pas (Q-02).
- **H-04 :** les runners macOS de la CI n'ont pas de périphérique de sortie audio ; le self-test ne doit pas dépendre du matériel (R-05).
- **H-05 :** le son de démonstration sert aussi aux tests automatisés et au self-test (E-08, PO-14).
- **H-06 :** les constantes du modèle physique (rampes, rattrapage, 2 à 35 ms, 150 ms, 12 %) sont des paramètres ; leur calibrage sur appareil (PO-03, PO-04, PO-15) ne change pas les exigences.
- **H-07 :** l'utilisateur importe des fichiers personnels non protégés ; ni compte ni synchronisation.
- **H-08 :** « iPhone/iPad récents » (SF-78) désigne une liste d'appareils de référence à fixer pour la recette (Q-01).

## 8. Risques et parades

| ID | Risque | Impact | Parades | Exigences | Épopées |
|---|---|---|---|---|---|
| R-01 | **Latence** geste→son > 20 ms : scratch injouable | Élevé | Tampon de 256 trames demandé au système (iOS et macOS) ; intégration dans le fil de rendu ; touches regroupées et prédites ; geste transmis au rendu sans passer par le fil principal ; prototype mesuré tôt (PO-07) avec un protocole de mesure reproductible | SF-78, SF-09 | EP2, EP4, EP1 |
| R-02 | **Temps réel audio en Swift** : allocations, comptage de références, verrous ou appels système dans le rendu → décrochages et clics | Élevé | Noyau de rendu en types valeur et tampons préalloués ; commandes par file sans verrou (atomiques) ; remplacement et libération des sons hors du fil de rendu (suppression d'un son chargé, SF-74) ; aucune journalisation dans le rendu ; contrôle à chaque revue QA | SF-77, RM-08 | EP1, EP2 |
| R-03 | **Multitouch SwiftUI** : les gestes SwiftUI n'exposent ni touches regroupées ou prédites ni suivi fiable de 3 contacts indépendants | Élevé | Surface tactile UIKit dédiée, intégrée à SwiftUI, pour les disques et le crossfader ; chaque contact attribué à sa commande dès son début (RM-60) ; annulation système = relâchement ; prototype sur iPad réel dès la première vague | SF-19, SF-78, RM-60, RM-61 | EP4 |
| R-04 | **Mac sans écran tactile** : un seul pointeur pour le disque et le crossfader | Moyen | Coupures momentanées et crossfader au clavier, trackpad relâché à 80 ms (SF-79, RM-59, §3.5) ; MIDI en P2 (E-10) ; lever IC-06 à IC-08 avant la story clavier | SF-79, RM-59 | EP5 |
| R-05 | **Runners CI macOS sans périphérique audio** : le moteur ne démarre pas, rien à « écouter » | Moyen | Self-test en rendu hors ligne (mode de rendu manuel d'AVAudioEngine, déjà amorcé dans `Sources/ScratchAudio/SelfTest.swift`), à étendre au son de démo avec des valeurs attendues ; DSP testé sous Linux ; le lancement sans sortie exerce SF-82 ; son réel recetté sur appareil | §7 P0, SF-82 | EP2, EP6 |
| R-06 | **Mémoire des sons longs** : 10 min en stéréo Float32 à 48 kHz ≈ 230 Mo par son, ≈ 460 Mo pour deux sons, davantage à 96 kHz ; arrêt par le système sur les appareils anciens | Élevé | Mesurer l'empreinte (PO-16) ; évaluer un stockage compact en mémoire (Int16 : ≈ 115 Mo par son) ; un seul tampon pour un même son chargé sur A et B (RM-57) ; aperçu de forme d'onde précalculé | SF-80 | EP2, EP1 |
| R-07 | **Repliement aux vitesses élevées** (> 2×, jusqu'à 16×) : artefacts métalliques | Moyen | Interpolation à bande limitée dont la coupure suit la vitesse, ou versions préfiltrées par octave (coût mémoire, voir R-06) ; mesure spectrale automatisée dans ScratchCore ; seuil chiffré à fixer (IC-11) | SF-77 | EP1 |
| R-08 | **Changement de fréquence de sortie** (44,1 → 48 kHz sur Mac) : reconversion longue d'un son de 10 min | Moyen | Reconversion hors du fil de rendu puis bascule atomique, ou compensation du rapport de fréquences à la lecture ; décision d'architecture | SF-80 | EP2 |
| R-09 | **Calibrage du modèle physique** : sensation artificielle ; si la vitesse est conservée à la saisie d'un disque en rotation, le filtre du 2ᵉ ordre dépasse puis revient vers le doigt (≈ 13 ms de son à 35 ms et 33⅓ RPM) | Moyen | Constantes paramétrables (H-06) ; tests de bornes en UL ; session de calibrage sur appareil avec un turntablist (PO-15) | SF-06, SF-22 | EP1 |
| R-10 | **Bibliothèque modifiée hors de l'app** (Fichiers, Finder) : entrée vers une copie absente | Moyen | Réconciliation de l'index au lancement et au chargement, erreur explicite (IC-10) | RM-48 | EP3 |
| R-11 | **Charge concentrée** : EP1 et EP2 portent 47 des 72 exigences (même développeur) | Moyen | Contrats d'interface publiés tôt par l'architecte ; stories EP1 testables sous Linux, menées en parallèle de l'UI grâce à des doublures de test | — | EP1, EP2 |

## 9. Questions ouvertes

| ID | Sujet | Statut v2.0 | Impact V1 | Arbitrage |
|---|---|---|---|---|
| PO-07 | Latence audio et tactile | Partiellement clos : objectifs fixés, mesure sur prototype | Valide l'architecture audio et tactile (R-01) | Architecte, après prototype |
| PO-08 | USB : MPC Sample, enregistrement dans Logic Pro | Ouvert : test sur matériel | Recette de SF-16 (persona 3) | QA, sur matériel |
| PO-12 | Rechargement des sons au relancement | Ouvert : non retenu en V1, à trancher pour la V1.1 | Aucun en V1 (SF-17) | PM |
| PO-14 | Contenu, taille et licence du son de démonstration | Ouvert : généré par l'app ou ressource libre de droits | Bloque SF-76 et le self-test (H-05) ; situe la démo en EP1 (générée) ou EP3 (ressource) | PM et PO, avant la première vague |
| PO-15 | Calibrage de la résistance (2 à 35 ms) | Ouvert : validation sur appareil | Sensation (persona 2) | PO, en recette |
| PO-16 | Durée maximale de 10 min et mémoire des anciens appareils | Ouvert : à réévaluer après mesure | Peut réduire la limite de SF-80 (R-06) | PM, après mesure |
| PO-11, PO-13 | Souffle et crépitement ; mappage MIDI | Ouverts, P2 | Aucun en V1 | — |
| Q-01 | Appareils de référence pour « récents » (SF-78) et la recette | Issu de l'analyse | Rend KPI-01 vérifiable | PM et QA |
| Q-02 | Sorties Bluetooth exclues de l'objectif de 20 ms ? | Issu de l'analyse | Recette de SF-78 (H-03) | PM |
| Q-03 | Arbitrage de IC-01 à IC-12 (section 10) | Issu de l'analyse | Priorités, stories et tests | PO |

## 10. Incohérences détectées

La spec v2.0 n'est pas modifiée. Chaque point est soumis au PO ; les pistes ne sont que des propositions.

> **Tranché par le PO** dans [`po-validation.md`](po-validation.md) et intégré à la spec v2.1 : IC-01 → D-01, IC-02 → D-02, IC-03 → D-03, IC-04 → D-04, IC-05 → D-05, IC-06 → D-06, IC-07 → D-07, IC-08 → D-08, IC-09 → D-10, IC-10 → D-11 et D-12, IC-11 → D-13 et D-14, IC-12 → D-17 ; Q-01 → D-14, Q-02 → D-15, Q-03 → registre complet.

| ID | Type | Constat | Conséquence et piste |
|---|---|---|---|
| IC-01 | Priorité | La feature 6.1 **[P0]** contient des scénarios dont l'exigence est **P1** ailleurs : « Recharger un son déjà importé sans accéder à Drive » (bibliothèque SF-74 : 6.13 [P1], recette P1, E-07 P1), « Importer un contenu déjà présent… » (SF-75 : recette P1), « Charger le son de démonstration » (SF-76 : E-08 P1), fichiers incompatibles, protégés ou corrompus (recette P1), « Importer un fichier trop long » (SF-80 : 6.15 [P1]). 6.3 [P0] « Lancer le son depuis le repère » suppose le repère (SF-69, P1). L'incohérence I-02 de la revue n'est donc résolue qu'en partie. | La matrice applique « P0 si un scénario P0 la vérifie » et marque ⚠ SF-20, SF-74, SF-75, SF-76, SF-80 et RM-58. Piste : passer ces scénarios en P1, ou passer en P0 le strict nécessaire (chargement depuis la bibliothèque, démo). |
| IC-02 | Priorité | La revue classe E-02 (courbe réglable, hamster) et E-06 (latence chiffrée) en P0 ; or 6.10 est [P1], la mesure de latence est un critère P1 et SF-78 n'a aucun scénario. | Matrice : SF-67 et SF-78 en P1 (⚠). Piste : confirmer P1 en gardant la conception basse latence dès EP2. |
| IC-03 | Contradiction | « Temps de rattrapage » : **durée** (SF-10, SF-68, 6.3 « en 60 ms environ », 6.9 « pendant environ 300 ms », recette P0) ou **constante de temps** (§5.1, point 2) ? Avec une constante de 60 ms, une réponse exponentielle n'atteint que 63 % de la vitesse du plateau à 60 ms et 95 % vers 180 ms. | Les tests de SF-10 et SF-68 en dépendent. Piste : définir le temps de rattrapage comme la durée pour atteindre la vitesse du plateau à un seuil donné. |
| IC-04 | Ambiguïté | 0.3 assimile sur Mac un « changement de configuration audio » à une interruption (STOP, SF-18, RM-56), mais 6.5 « Changer de périphérique de sortie sur Mac » attend une continuité sans STOP. L'arrêt sur perte de périphérique ou de casque (6.5) ne figure dans aucune SF ni RM (SF-16 : « sans plantage »). | Piste : une règle unique des changements de route (choix volontaire ou perte), par plateforme. |
| IC-05 | Contradiction | SF-19 exige 3 contacts (disque A, disque B, crossfader) « sur iPhone/iPad », mais l'iPhone en portrait n'affiche qu'une platine (§3.4) ; les scénarios 6.8 ne visent que l'iPad. | Piste : limiter SF-19 aux dispositions où les deux disques sont visibles. |
| IC-06 | Lacune | La coupure momentanée F/J (§3.5, 6.14) ouvre la voie malgré un crossfader fermé, mais le gain d'une voie n'est défini que comme fader × crossfader (SF-65, RM-52). Effet non défini si la voie est déjà ouverte ou si le fader est à 0. | Piste : intégrer la coupure momentanée à la formule de gain et préciser ces cas. |
| IC-07 | Conflit | Sur Mac, ← et → déplacent le crossfader (§3.5), alors que SF-83 et 6.16 veulent des curseurs ajustables au clavier quand ils ont le focus, et une tabulation entre commandes. | Piste : préciser la priorité entre raccourcis globaux et commande ayant le focus. |
| IC-08 | Ambiguïté | Les raccourcis §3.5 (Q/P, A/S, L/K, F/J, Z/X, « , » et « . ») suivent les positions d'un clavier QWERTY ; en AZERTY, Q/A et Z/W sont permutés et « . » demande Maj. Caractère ou position physique ? | Piste : décision UX (`front-end-spec.md`), reprise dans l'aide des raccourcis (§3.3). |
| IC-09 | Ambiguïté | Le repère doit passer sous la tête quand celle-ci est au CUE (SF-69, 6.11), mais l'angle du disque se découple de la position au sillon fermé (RM-55), au rappel du CUE disque tenu (6.6) et au needle drop (SF-71). RM-13 n'exempte que le sillon fermé. | Piste : recalculer la place du repère sur l'étiquette après chaque saut de position (architecture et UX). |
| IC-10 | Lacune | `Documents/Banque de sons/` est visible dans Fichiers et le Finder (§5.3, 0.3) : l'utilisateur peut y supprimer une copie, cas que RM-48 interdit sans dire comment le détecter. Le nommage des copies en cas de collision (SF-60, RM-43) est P2. | Piste : réconciliation de l'index ; règle de nommage minimale en V1. |
| IC-11 | Testabilité | Critères non chiffrés : repliement « atténué » au-delà de 2× (SF-77), appareils « récents » (SF-78), « sans retard visible » (SF-70), indicateur de saturation « éteint ou signale l'action du limiteur » (6.8). | Piste : seuils mesurables fixés par l'architecte et la QA. |
| IC-12 | Mineure | SF-64 étend « toutes les exigences SF-03 à SF-24 » à chaque platine, y compris des exigences globales (SF-16, SF-19, SF-20). Le caractère global des durées moteur et du rattrapage n'est qu'implicite (§3.3, SF-17). | Piste : lire « sauf mention contraire » (§4) ; durées globales. |

## 11. Suite

- **John (PM) :** PRD à partir de ce brief et de la matrice ; arbitrage de IC-01, IC-02, Q-01 et Q-02.
- **Sally (UX) :** IC-05, IC-07, IC-08 et IC-09 dans `front-end-spec.md`.
- **Winston (architecte) :** R-01 à R-03 et R-05 à R-08 ; IC-03, IC-04, IC-06 et IC-11 ; placement de la logique testable sous Linux.
- **Sarah (PO) :** validation croisée et décision sur la section 10. **Quinn (QA) :** lacunes de couverture et exigences à recetter sur appareil (`traceability.md`, sections 6 et 7).
