# Revue des spécifications — v1.9 « Platine Scratch 33 » → v2.0 « ScratchApp »

- **Date :** 14 novembre 2026
- **Document revu :** [`archive/platine_scratch_specifications_v1_9.md`](archive/platine_scratch_specifications_v1_9.md)
- **Document produit :** [`scratchapp_specifications_v2_0.md`](archive/scratchapp_specifications_v2_0.md), archivé depuis ; la version qui fait foi est la [v2.1](scratchapp_specifications_v2_1.md), qui intègre les décisions de la validation PO ([`po-validation.md`](../bmad/po-validation.md))
- **But visé :** pouvoir scratcher des pistes **à la façon d'une double platine vinyle 33 tours** (deux platines et une table de mixage), sur iPhone, iPad et Mac.

## 1. Incohérences corrigées

| # | Incohérence constatée en v1.9 | Correction v2.0 |
|---|---|---|
| I-01 | **Collision d'identifiants** : RM-43 à RM-45 (copie locale, section 5, v1.8) et RM-43 à RM-46 (nommage, section 10.5, v1.9, confirmé par le journal) portent les mêmes numéros. | Les règles de copie deviennent **RM-47 à RM-49**. Les règles de nommage gardent RM-43 à RM-46, comme l'indique le journal 1.9. |
| I-02 | Le **scénario P0** « Recharger un son déjà importé… depuis la bibliothèque locale disponible » repose sur une bibliothèque dont l'interface est **P2**. En V1, la copie locale est obligatoire (SF-02), mais rien ne permet de la recharger. | Ajout d'une **bibliothèque minimale V1** (SF-74) : lister, charger sur A ou B, supprimer. La banque P2 (micro, renommage) l'étend. |
| I-03 | Le **Background** de 6.3 impose « le moteur tourne à 33⅓ RPM », alors que deux scénarios de la même feature exigent un moteur arrêté. | Feature scindée en blocs Gherkin `Rule:` (« Moteur actif », « Moteur arrêté », « Gestes particuliers »), chacun avec son Background. |
| I-04 | **SF-14** impose de « bloquer la position à la fin », alors que **PO-05** laisse ouvert le comportement en fin de sample (arrêt, boucle, silence). | Décision : **sillon fermé** (RM-55). La tête reste à la fin en silence, le disque tourne, et un geste arrière revient immédiatement dans le son. PO-05 est clos. |
| I-05 | **Hors périmètre V1 : « deuxième platine »**, alors que le but est la double platine. Le crossfader sur une platine unique pose un problème non résolu (PO-02). | **Deux platines et table de mixage en V1** (SF-64 à SF-67). PO-02 est clos. |
| I-06 | **Plateformes** limitées à iPhone/iPad, alors que l'application doit aussi tourner sur macOS. Plusieurs exigences ne s'appliquent qu'à iOS : Fichiers, « Sur mon iPhone », interruptions AVAudioSession, multitouch. | macOS 14+ ajouté. Tableau d'équivalences (0.3), commandes Mac (SF-79, 3.5, 6.14), cycle de vie Mac (SF-81), sortie Mac (SF-16). |
| I-07 | **SF-17** conserve « RPM, pitch et crossfader », mais le scénario « Restaurer les préférences » ne vérifie que RPM et pitch. | SF-17 précisé (préférences par platine, crossfader, courbe, hamster, faders, durées moteur) et scénario complété. |
| I-08 | **SF-15** exige une confirmation « pendant la lecture » sans traiter le cas d'une platine chargée à l'arrêt. L'articulation avec la copie locale n'est pas précisée : en cas de refus, que devient la copie ? | Confirmation seulement si la platine est **active**. Une platine à l'arrêt est remplacée directement. En cas de refus, la copie reste dans la bibliothèque. Scénarios ajoutés. |
| I-09 | Section 3 : « Définir CUE / Rappeler CUE (**ou interaction équivalente à préciser**) », alors que le Gherkin utilise un unique bouton « CUE ». | Deux boutons distincts, **SET CUE** et **CUE**. Gherkin aligné. |
| I-10 | **SF-10** « reprise progressive » au relâchement, sans durée, et PO-03/PO-04 ouverts. Une reprise lente rend impossibles les scratchs de type « release », où le son doit partir instantanément. | **Feutrine** et **temps de rattrapage** (60 ms par défaut, réglable de 0 à 300 ms), durées de démarrage et de freinage chiffrées (SF-68, 5.1). |
| I-11 | **RM-04** (« le déplacement angulaire détermine le déplacement temporel ») ne quantifie pas la correspondance. Le comportement à 45 RPM est ambigu : le son est-il lu à vitesse normale ou accélérée ? | **RM-50** : un tour vaut 1,8 s de son, avec une gravure virtuelle à 33⅓. À 45 RPM, lecture 1,35× plus rapide, comme un vrai 33 tours joué en 45. Cela reste cohérent avec « la lecture suit la nouvelle vitesse » (6.2). |
| I-12 | Exemples de pitch donnés à 33⅓ seulement. Pas de résolution du pas. | Exemples à 45 RPM (41,40 / 45,00 / 48,60), pas de 0,1 % et remise à zéro (SF-11). |
| I-13 | **SF-43** (identification par empreinte du contenu) et **SF-63** (identifiant interne stable de la copie) définissent deux identités concurrentes. Si un même contenu est importé deux fois, faut-il deux entrées ou une seule ? | **RM-58** : UUID stable **et** empreinte SHA-256. Dédoublonnage par contenu (SF-75). Le point ouvert « anti-doublons » de 10.5 est clos. |
| I-14 | **Conventions de nommage divergentes** : `scratch_2026-11-12_102400.wav` (SF-38, mix) et `REC_AAAAMMJJ_HHMMSS.wav` (SF-54/61, micro). | Mix : `MIX_AAAAMMJJ_HHMMSS.wav`. Micro : `REC_…` inchangé. |
| I-15 | **RM-01** (« sans fichier, aucun son ») contredit **SF-32** (crépitement audible sans fichier) lorsque l'option P2 sera activée. | Amendement explicite de RM-01, applicable à l'implémentation du crépitement (10.2). |
| I-16 | État du moteur après interruption non précisé : « suspendre » ou « arrêter » ? Et comment reprendre ? | **RM-56** : passage immédiat à STOP sur chaque platine, positions conservées, reprise par START. |
| I-17 | « Démarrer sans fichier » (6.2) : on ignore si le plateau tourne (PO-01 ouvert). | Le plateau tourne, sans son, et l'import ou la démo sont proposés. PO-01 est clos. |
| I-18 | **SF-10, moteur arrêté** : « immobilité » au relâchement, ce qui est physiquement incohérent si le disque est lancé. | Ralentissement naturel en 150 ms au plus, sans reprise motorisée (SF-10, 5.1). |
| I-19 | « Précision de conception » : « non retenu… **en V1.1** », mélange entre la version du document (1.1) et la version du produit (V1). | Corrigé en « non retenu en V1 ». |
| I-20 | PO-09 (arrière-plan) ouvert alors que SF-18 et RM-10 en dépendent. | **SF-81** : pas d'audio en arrière-plan sur iOS/iPadOS en V1 ; sur Mac, la lecture continue fenêtre inactive. PO-09 est clos. |
| I-21 | Résistance et moteur : RM-11 ne dit pas si un disque « lourd » met plus longtemps à repartir. | **RM-54** : la résistance n'affecte ni démarrage, ni freinage, ni rattrapage. Scénario ajouté (6.7). |
| I-22 | Emplacements de stockage dispersés entre SF-02 (« dossier local »), SF-37 (« Enregistrements ») et SF-54 (« Banque de sons »). | Tableau unique de stockage (5.3) : `Documents/Banque de sons/`, `Documents/Enregistrements/`, index en `Application Support`. |

## 2. Scénarios ajoutés ou complétés

**Import (6.1) :** import depuis le Finder sur Mac, M4A ALAC, fichier protégé (DRM), fichier corrompu ou vide, fichier trop long (> 10 min), contenu déjà présent (dédoublonnage), chargement de la démo. L'échec de copie précise qu'aucune entrée de bibliothèque n'est ajoutée.

**Moteur (6.2) :** STOP pendant que le disque est retenu, START pendant le freinage, réglage des durées de démarrage et de freinage, START sans fichier (plateau qui tourne).

**Scratch (6.3) :** inversions rapides (baby scratch) sans clic, « release » depuis le repère, saisie d'un disque en rotation, geste commencé hors du disque, deuxième doigt ignoré, toucher annulé par le système, doigt au centre du disque.

**Crossfader et mixage (6.4, 6.10) :** voie A↔B, cut-in en 3 % de course, fader de voie, courbe douce à −3 dB, tableau de gains par courbe, hamster, persistance des réglages.

**Cycle de vie (6.5) :** remplacement d'une platine à l'arrêt (sans confirmation), copie conservée après un refus, arrière-plan iOS, fenêtre inactive sur Mac, casque débranché, changement de périphérique Mac à une autre fréquence, aucune sortie disponible.

**Pitch et CUE (6.6) :** exemples à 45 RPM, remise à zéro, SET CUE et CUE pendant que le disque est tenu, CUE propre à chaque son et à chaque platine.

**Nouvelles features :**

- Double platine (6.8) : indépendance, scratch de A sur le rythme de B, même son sur A et B, deux disques et trois contacts simultanés sur iPad, bascule A/B sur iPhone, absence de saturation.
- Feutrine (6.9).
- Repère, forme d'onde et needle drop (6.11).
- Amorce et sillon fermé, son très court (6.12).
- Bibliothèque et glisser-déposer (6.13).
- Commandes Mac (6.14) : souris, trackpad, coupure au clavier pendant un scratch à la souris, transport, crossfader au clavier, raccourcis inactifs pendant une saisie, redimensionnement de la fenêtre.
- Formats et fréquences (6.15).
- Accessibilité (6.16).

## 3. Évolutions indispensables pour scratcher « comme sur une double platine 33T »

| ID | Évolution | Pourquoi c'est indispensable | Priorité |
|---|---|---|---|
| **E-01** | **Deux platines A/B + table de mixage** (faders de voie, VU-mètres, limiteur) | Une installation de scratch, c'est deux platines et un mixeur. On scratche une phrase sur une platine pendant que l'autre joue la rythmique, et on passe de l'une à l'autre au crossfader. Avec une seule platine, le crossfader se réduit à un bouton mute. | P0 |
| **E-02** | **Crossfader de scratch** : courbe réglable jusqu'à la coupure franche, cut-in ≤ 3 %, hamster, coupures momentanées au clavier | Les techniques de coupure (transformer, chirp, flare, crab) exigent une ouverture quasi instantanée sur une très courte course, comme sur une vraie table de mixage de scratch. La v1.9 parle d'une « courbe de gain définie »… jamais définie. | P0 |
| **E-03** | **Feutrine et couple moteur** : le plateau tourne sous le disque retenu, rattrapage en 60 ms | Sur une vraie platine, on retient le disque pendant que le plateau tourne dessous, puis on le lâche : le son part instantanément. C'est la base du scratch « release » et du cueing. Une reprise « progressive » non bornée (v1.9) le rend impossible. | P0 |
| **E-04** | **Repère (autocollant), forme d'onde et needle drop** | Les DJ scratch collent un repère sur l'étiquette pour retrouver l'attaque du son à l'œil. Sans repère ni forme d'onde, impossible de répéter un scratch précis. | P1 |
| **E-05** | **Amorce silencieuse de 2 s et sillon fermé** | Pour « attaquer » un son, il faut pouvoir reculer avant son début, puis le pousser. Le blocage strict à 0 s de la v1.9 rend l'attaque impossible. En fin de son, le sillon fermé reproduit le vinyle. | P1 |
| **E-06** | **Moteur audio temps réel de qualité** : intégration de la position à la fréquence audio, interpolation cubique, anti-repliement, objectifs de latence chiffrés | Le scratch est un jeu d'inversions très rapides : toute marche de vitesse ou latence > 20 ms se sent immédiatement au doigt et s'entend (clics, grésillements). | P0 |
| **E-07** | **Bibliothèque minimale V1 + dédoublonnage** | Une session de scratch demande de changer souvent de son sur l'une ou l'autre platine, sans repasser par Fichiers. Corrige aussi l'incohérence I-02. | P1 |
| **E-08** | **Son de démonstration intégré** | Pour essayer immédiatement le scratch et pour les tests automatisés (CI macOS), sans dépendre d'un fichier de l'utilisateur. | P1 |
| **E-09** | **Commandes Mac** : souris, trackpad, clavier, menus | Sans écran tactile, le geste simultané « disque + crossfader » doit passer par souris + clavier, comme un DJ qui scratche d'une main et coupe de l'autre. | P0 |
| **E-10** | Contrôleur MIDI (P2) | Seule façon d'avoir deux mains sur deux disques physiques sur Mac. Utile aussi sur iPad. | P2 |
| **E-11** | Plages de pitch étendues (P2) | Confort, non bloquant. | P2 |
| **E-12** | Accessibilité de base | Exigence App Store et qualité. | P1 |

## 4. Points restant ouverts

PO-07 (latence : mesure sur prototype), PO-08 (MPC Sample et Logic Pro : test sur matériel), PO-11 (P2), PO-12 (rechargement de session), PO-13 (mappage MIDI), PO-14 (contenu du son de démonstration), PO-15 (calibrage de la résistance), PO-16 (durée maximale et mémoire).
