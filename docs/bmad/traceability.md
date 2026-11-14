# ScratchApp — Matrice de traçabilité V1

- **Auteur :** 📊 Mary, Analyst BMAD
- **Date :** 14 novembre 2026
- **Source :** spécifications v2.0, désormais archivées ([`archive/scratchapp_specifications_v2_0.md`](../specs/archive/scratchapp_specifications_v2_0.md)). Aucune exigence nouvelle n'est introduite. La spec qui fait foi est la [v2.1](../specs/scratchapp_specifications_v2_1.md) : mêmes identifiants, décisions du PO intégrées.
- **Validation PO ([`po-validation.md`](po-validation.md)) :** les priorités marquées ⚠ sont tranchées (D-01, D-02) : SF-20, SF-76, SF-80 et RM-58 restent P0 ; SF-74, SF-75, SF-67 et SF-78 sont P1. Trois scénarios de features [P0] portent le tag `@P1` (6.1 « Recharger un son déjà importé sans accéder à Drive », « Importer un contenu déjà présent dans la bibliothèque » ; 6.2 « Régler les durées de démarrage et de freinage »). La v2.1 ajoute 11 scénarios (6.5, 6.8, 6.10, 6.11, 6.13, 6.14, 6.16), à rattacher par Quinn dans la recette (6.3).
- **Artefact compagnon :** [`project-brief.md`](project-brief.md) (personas, risques, incohérences IC-01 à IC-12).
- **Périmètre :** les 72 exigences V1 : SF-01 à SF-24, SF-64 à SF-83 (44 SF), RM-01 à RM-13 et RM-47 à RM-61 (28 RM).

## 1. Conventions

**Priorité.** Elle est déduite des features Gherkin (§6 de la spec) et des critères de recette (§7) :
une exigence est **P0** si au moins un scénario d'une feature [P0] la vérifie (ses `Then` portent sur elle) ou si un critère de recette P0 la couvre ; sinon elle est **P1**.
Le marqueur **⚠** signale une priorité en conflit avec une autre source de la spec ou de la revue (voir le brief, section 10).

**Épopées.** EP1 à EP6, selon `AGENT_RULES.md`. La première épopée citée porte l'exigence ; les suivantes y contribuent.

| Épopée | Titre | Module(s) |
|---|---|---|
| EP1 | Cœur audio temps réel (physique des platines, rendu, table de mixage) | ScratchCore |
| EP2 | Moteur audio Apple (AVAudioEngine, décodage, session, self-test) | ScratchAudio |
| EP3 | Bibliothèque locale et préférences | ScratchLibrary |
| EP4 | Interface : platines, table de mixage, forme d'onde, dispositions | ScratchUI |
| EP5 | Commandes Mac, glisser-déposer et accessibilité | ScratchUI, App |
| EP6 | Intégration de l'application, cycle de vie et recette | App, ScratchUI (AppModel), CI |

**Types de vérification.**

| Code | Type | Où |
|---|---|---|
| UL | Test unitaire Linux | `swift test` sur ScratchCore et ScratchLibrary (CI Linux, `scripts/linux-test.sh`) |
| TM | Test macOS | `swift test` complet sur le runner macOS (ScratchAudio, ScratchUI, AppModel), builds macOS et iOS |
| ST | Self-test CI | `ScratchApp --selftest`, lancement de l'app et capture d'écran sur le runner macOS (contenu défini par l'architecture, EP2) |
| MA | Manuel sur appareil | iPhone, iPad ou Mac physique, avec les périphériques réels |

Le code UL suppose que la logique concernée (calcul, état, persistance) est placée dans ScratchCore ou ScratchLibrary ; l'architecture le confirmera.

**Colonne Gherkin.** Numéro de feature, puis titres exacts des scénarios séparés par « · ». « (toutes) » désigne tous les scénarios de la feature.

## 2. Exigences fonctionnelles

### 2.1 SF-01 à SF-24

| ID | Résumé | Prio | Épopée | Module(s) | Section(s) Gherkin | Vérification |
|---|---|---|---|---|---|---|
| SF-01 | Ouverture sans lecture ; import et démo proposés sur une platine vide | P0 | EP4, EP6 | ScratchUI, App | 6.1 Premier lancement sans fichier ; 6.2 Démarrer sans fichier | TM, ST |
| SF-02 | Import par le sélecteur du système, copie locale, refus des fichiers non décodables ou protégés, erreurs de copie | P0 | EP3, EP2, EP4, EP5 | ScratchLibrary, ScratchAudio, ScratchUI, App | 6.1 Importer un fichier WAV · Importer un format audio compatible · Importer depuis le Finder sur Mac · Échec de copie faute d'espace · Un import ne modifie pas le fichier source · Annuler l'importation · Importer un fichier incompatible · Importer un fichier protégé · Importer un fichier corrompu ou vide | UL, TM, MA |
| SF-03 | Après chargement : titre, durée, tête à 0 s, repère aligné, moteur arrêté | P0 | EP1, EP4 | ScratchCore, ScratchUI | 6.1 Importer un fichier WAV · Charger le son de démonstration ; 6.5 Charger un deuxième fichier sur une platine active | UL, TM |
| SF-04 | START : accélération sur la durée de démarrage (0,7 s), l'audio suit la vitesse réelle | P0 | EP1, EP4 | ScratchCore, ScratchUI | 6.2 Démarrer la platine à 33 tours · Sélectionner 45 tours · Modifier la vitesse pendant la lecture · Démarrer sans fichier · Appuyer sur START pendant le freinage ; 6.9 Démarrage court | UL, ST |
| SF-05 | STOP : décélération (1,0 s), position conservée, scratch possible moteur arrêté | P0 | EP1, EP4 | ScratchCore, ScratchUI | 6.2 Arrêter la platine · Appuyer sur STOP pendant que je retiens le disque · Régler les durées de démarrage et de freinage ; 6.3 Scratcher avec le moteur arrêté | UL |
| SF-06 | Prise en main prioritaire ; doigt immobile = disque retenu ; plateau qui tourne dessous | P0 | EP1, EP4 | ScratchCore, ScratchUI | 6.3 Poser le doigt sur le disque · Maintenir un disque immobile · Saisir le disque en rotation ; 6.9 Le plateau tourne sous le disque retenu ; 6.14 Retenir et scratcher à la souris | UL, MA |
| SF-07 | Scratch avant | P0 | EP1, EP4 | ScratchCore, ScratchUI | 6.3 Pousser le disque vers l'avant · Faire un scratch avant-arrière · Scratcher avec le moteur arrêté ; 6.14 Retenir et scratcher à la souris | UL, MA |
| SF-08 | Scratch arrière : lecture réellement inversée | P0 | EP1, EP4 | ScratchCore, ScratchUI | 6.3 Faire reculer le disque · Faire un scratch avant-arrière · Scratcher avec le moteur arrêté ; 6.14 Retenir et scratcher à la souris | UL, MA |
| SF-09 | Vitesse et hauteur suivent le geste (interpolation SF-77) | P0 | EP1 | ScratchCore | 6.3 Pousser le disque vers l'avant · Faire reculer le disque · Varier la vitesse du scratch | UL, MA |
| SF-10 | Relâchement : rattrapage en 60 ms moteur actif ; arrêt en ≤ 150 ms moteur arrêté, sans reprise | P0 | EP1 | ScratchCore | 6.3 Relâcher le disque moteur actif · Lancer le son depuis le repère (« release ») · Relâcher le disque moteur arrêté ; 6.2 Appuyer sur STOP pendant que je retiens le disque ; 6.9 Rattrapage réglable · Rattrapage plus lent ; 6.14 Retenir et scratcher à la souris | UL, MA |
| SF-11 | Pitch −8 % à +8 % par pas de 0,1 %, hauteur incluse, remise à 0 en un geste | P1 | EP1, EP4 | ScratchCore, ScratchUI | 6.6 Modifier le pitch · Remettre le pitch à zéro ; 6.16 Régler le pitch par les actions d'accessibilité | UL, TM |
| SF-12 | Le crossfader ne change que le gain des voies | P0 | EP1, EP4 | ScratchCore, ScratchUI | 6.4 Fermer complètement la voie A au crossfader · Ouvrir la voie A au crossfader · Scratch avec coupure rythmique · Crossfader en position intermédiaire avec courbe douce | UL |
| SF-13 | SET CUE / CUE ; CUE à 0 s par défaut ; propre à chaque platine, réinitialisé au chargement | P1 | EP1, EP4 | ScratchCore, ScratchUI | 6.6 Mémoriser un point CUE · Revenir au point CUE · Rappeler CUE sans point enregistré · Définir un CUE pendant que je retiens le disque · Rappeler le CUE pendant que je retiens le disque · Le CUE est propre à chaque son | UL, MA |
| SF-14 | Tête bornée à [−2 s ; durée], blocage aux bornes, sans lecture hors limites ni clic | P1 | EP1 | ScratchCore | 6.12 (toutes) | UL |
| SF-15 | Remplacement : confirmation si la platine est active, sinon direct ; retour à l'état SF-03 ; l'autre platine intacte | P1 | EP6, EP4, EP1 | App, ScratchUI (AppModel), ScratchCore | 6.5 Charger un deuxième fichier sur une platine active · Charger un deuxième fichier sur une platine à l'arrêt · Refuser le remplacement ; 6.13 Déposer un fichier sur une platine | TM |
| SF-16 | Route audio active (iOS) ou sortie par défaut (macOS), USB compris ; suivi des changements sans plantage | P1 | EP2, EP4 | ScratchAudio, ScratchUI | 6.5 Brancher une interface audio USB · Perdre le périphérique audio · Débrancher le casque (iPhone/iPad) · Changer de périphérique de sortie sur Mac | TM, MA |
| SF-17 | Préférences conservées (par platine : RPM, pitch, résistance ; table ; durées) sans relance audio ni rechargement des sons | P1 | EP3, EP6 | ScratchLibrary, App | 6.5 Restaurer les préférences ; 6.7 Restaurer le réglage mémorisé ; 6.10 Conserver les réglages de crossfader | UL, TM |
| SF-18 | Interruption système : chaque moteur à STOP, positions conservées, reprise manuelle | P1 | EP2, EP6 | ScratchAudio, App | 6.5 Recevoir une interruption système (iPhone/iPad) | TM, MA |
| SF-19 | Au moins 3 contacts simultanés et indépendants (disque A, disque B, crossfader ou fader) | P0 | EP4 | ScratchUI | 6.4 Scratch avec coupure rythmique ; 6.8 Scratcher les deux disques en même temps sur iPad · Trois contacts simultanés | MA, TM |
| SF-20 | Fonctionnement entièrement hors ligne | P0 ⚠ | EP6, EP3 | App, ScratchLibrary | 6.1 Recharger un son déjà importé sans accéder à Drive | UL, MA |
| SF-21 | Curseur « Résistance du vinyle » 0–100 % par platine, ajustable en temps réel | P1 | EP4, EP1 | ScratchUI, ScratchCore | 6.7 Afficher le réglage sur l'interface principale · Modifier la résistance pendant le scratch | UL, TM |
| SF-22 | Résistance élevée = accélérations amorties ; le son suit le disque simulé | P1 | EP1 | ScratchCore | 6.7 Réduire la résistance · Augmenter la résistance | UL, MA |
| SF-23 | Changer la résistance sans saut de position, clic ni inversion inattendue | P1 | EP1 | ScratchCore | 6.7 Augmenter la résistance · Scratcher en sens inverse avec une résistance élevée · Modifier la résistance pendant le scratch | UL |
| SF-24 | Résistance mémorisée par platine, sans lecture automatique | P1 | EP3, EP6 | ScratchLibrary, App | 6.7 Restaurer le réglage mémorisé | UL, TM |

### 2.2 SF-64 à SF-83

| ID | Résumé | Prio | Épopée | Module(s) | Section(s) Gherkin | Vérification |
|---|---|---|---|---|---|---|
| SF-64 | Deux platines A et B identiques et indépendantes | P0 | EP1, EP6 | ScratchCore, App, ScratchUI (AppModel) | 6.8 Les platines sont indépendantes · Scratcher A pendant que B joue · Charger le même son sur les deux platines · Passer d'une platine à l'autre sur iPhone en portrait ; 6.6 Le CUE est propre à chaque son | UL, TM |
| SF-65 | Table : faders de voie, crossfader, VU-mètres ; gain = fader × crossfader ; marge et limiteur doux | P0 | EP1, EP4 | ScratchCore, ScratchUI | 6.4 Fader de voie ; 6.8 Pas de saturation à la somme des deux voies | UL, ST |
| SF-66 | Courbe continue douce (−3 dB au centre) ↔ coupure franche (cut-in ≤ 3 %), coupure franche par défaut | P0 | EP1, EP4 | ScratchCore, ScratchUI | 6.4 Ouvrir la voie avec un déplacement minimal (cut-in) · Crossfader en position intermédiaire avec courbe douce ; 6.10 Gain des voies selon la courbe | UL |
| SF-67 | Hamster : inversion du crossfader, transition lissée ≤ 5 ms | P1 ⚠ | EP1, EP4 | ScratchCore, ScratchUI | 6.10 Activer le hamster · Conserver les réglages de crossfader | UL |
| SF-68 | Feutrine : plateau non arrêté par la prise ; rattrapage 0–300 ms (60 ms) ; démarrage et freinage 0,1–5 s | P0 | EP1, EP4 | ScratchCore, ScratchUI | 6.9 (toutes) ; 6.3 Poser le doigt sur le disque · Relâcher le disque moteur actif ; 6.2 Régler les durées de démarrage et de freinage ; 6.7 La résistance ne ralentit pas le rattrapage | UL, MA |
| SF-69 | Repère sur l'étiquette, à l'angle du CUE (ou de 0 s), qui tourne avec le disque | P1 | EP4, EP1 | ScratchUI, ScratchCore | 6.11 Le repère suit le disque ; 6.6 Mémoriser un point CUE | UL, MA |
| SF-70 | Forme d'onde zoomée (±1,8 s) et aperçu complet, tête et CUE, ≥ 60 i/s | P1 | EP4, EP1 | ScratchUI, ScratchCore | 6.11 La forme d'onde suit le scratch | TM, MA |
| SF-71 | Needle drop sur l'aperçu, état du moteur conservé, ignoré disque tenu, lissé ≤ 5 ms | P1 | EP4, EP1 | ScratchUI, ScratchCore | 6.11 Positionner la tête sur l'aperçu (needle drop) · Needle drop ignoré pendant que je retiens le disque | UL, TM |
| SF-72 | Amorce silencieuse de 2 s (−2 s à 0), position initiale 0 s | P1 | EP1 | ScratchCore | 6.12 Reculer dans l'amorce · Dépasser la borne de l'amorce en reculant | UL |
| SF-73 | Glisser-déposer sur une platine (Fichiers sur iPad, Finder sur Mac) ; refus avec message si incompatible | P1 | EP5, EP3 | ScratchUI, App, ScratchLibrary | 6.13 Déposer un fichier sur une platine · Déposer un fichier non audio | TM, MA |
| SF-74 | Bibliothèque minimale : liste, chargement sur A ou B, suppression confirmée, démo en tête, persistance | P0 ⚠ | EP3, EP4 | ScratchLibrary, ScratchUI | 6.13 Consulter la bibliothèque · Charger un son de la bibliothèque sur la platine B · Supprimer un son non chargé · Supprimer un son chargé sur une platine · Le son de démonstration ne peut pas être supprimé · Retrouver la bibliothèque après relancement ; 6.1 Recharger un son déjà importé sans accéder à Drive | UL, TM |
| SF-75 | Dédoublonnage par empreinte SHA-256 | P0 ⚠ | EP3 | ScratchLibrary | 6.1 Importer un contenu déjà présent dans la bibliothèque | UL |
| SF-76 | Son de démonstration libre de droits, jamais chargé automatiquement | P0 ⚠ | EP3, EP4, EP1 ou EP2 (PO-14) | ScratchLibrary, ScratchUI | 6.1 Premier lancement sans fichier · Charger le son de démonstration ; 6.13 Consulter la bibliothèque · Le son de démonstration ne peut pas être supprimé | UL, ST |
| SF-77 | Interpolation ≥ cubique, inversions continues, repliement atténué > 2×, vitesse bornée à ±16×, paramètres lissés à la fréquence audio | P0 | EP1 | ScratchCore | 6.3 Faire un scratch avant-arrière · Enchaîner des inversions rapides (baby scratch) · Varier la vitesse du scratch | UL, ST, MA |
| SF-78 | Tampon ≤ 256 trames à 48 kHz ; latence geste→son ≤ 20 ms ; touches regroupées et prédites ; mesure consignée | P1 ⚠ | EP2, EP4, EP6 | ScratchAudio, ScratchUI | Aucune (critère de recette P1 seulement) | MA, TM |
| SF-79 | Mac : clic-glisser, défilement trackpad (relâché à 80 ms), clavier 3.5, menus Fichier, Platine, Table | P0 | EP5 | ScratchUI, App | 6.14 (toutes) ; 6.1 Importer depuis le Finder sur Mac | TM, MA |
| SF-80 | Mono dupliqué, multicanal réduit en stéréo, conversion de fréquence sans changer la hauteur, 50 ms à 10 min | P0 ⚠ | EP2 | ScratchAudio | 6.15 (toutes) ; 6.1 Importer un fichier trop long ; 6.5 Changer de périphérique de sortie sur Mac | TM |
| SF-81 | iOS : STOP et sortie coupée en arrière-plan ; Mac : lecture continue fenêtre inactive, fermer la dernière fenêtre quitte | P1 | EP6, EP2 | App, ScratchAudio | 6.5 Passer en arrière-plan (iPhone/iPad) · Fenêtre inactive sur Mac | TM, MA |
| SF-82 | « Sortie audio indisponible » affiché, interface utilisable, nouvel essai automatique, jamais de plantage | P1 | EP2, EP6, EP4 | ScratchAudio, App, ScratchUI | 6.5 Aucune sortie audio disponible | TM, ST |
| SF-83 | Libellés VoiceOver, réglages par actions d'accessibilité et clavier Mac, contraste WCAG AA | P1 | EP5, EP4 | ScratchUI, App | 6.16 (toutes) | TM, MA |

## 3. Règles métier

### 3.1 RM-01 à RM-13

| ID | Résumé | Prio | Épopée | Module(s) | Section(s) Gherkin | Vérification |
|---|---|---|---|---|---|---|
| RM-01 | Sans son chargé, une platine n'émet aucun son | P0 | EP1 | ScratchCore | 6.1 Premier lancement sans fichier ; 6.2 Démarrer sans fichier | UL, ST |
| RM-02 | Vitesse nominale initiale 33⅓ RPM | P0 | EP1, EP3 | ScratchCore, ScratchLibrary | 6.2 Démarrer la platine à 33 tours (valeur initiale non vérifiée explicitement) | UL |
| RM-03 | Le toucher est prioritaire sur le moteur | P0 | EP1 | ScratchCore | 6.3 Poser le doigt sur le disque ; 6.2 Appuyer sur STOP pendant que je retiens le disque | UL |
| RM-04 | Le déplacement angulaire détermine le déplacement temporel (RM-50) | P0 | EP1 | ScratchCore | 6.3 Pousser le disque vers l'avant · Faire reculer le disque ; 6.12 Reculer dans l'amorce | UL |
| RM-05 | Rotation inverse = lecture inverse réelle, pas un bruit préenregistré | P0 | EP1 | ScratchCore | 6.3 Faire reculer le disque | UL |
| RM-06 | Crossfader et faders ne changent jamais la position | P0 | EP1 | ScratchCore | 6.4 Fermer complètement la voie A au crossfader · Ouvrir la voie A au crossfader · Crossfader en position intermédiaire avec courbe douce · Fader de voie | UL |
| RM-07 | Reprise motorisée au relâchement seulement si le moteur est actif | P0 | EP1 | ScratchCore | 6.3 Relâcher le disque moteur arrêté ; 6.2 Appuyer sur STOP pendant que je retiens le disque | UL |
| RM-08 | Variations de vitesse et de gain sans discontinuité audible | P0 | EP1 | ScratchCore | 6.3 Faire un scratch avant-arrière · Enchaîner des inversions rapides (baby scratch) · Relâcher le disque moteur actif ; 6.2 Appuyer sur START pendant le freinage | UL, MA |
| RM-09 | Jamais d'échantillon lu hors des bornes ; l'amorce est un silence virtuel | P1 | EP1 | ScratchCore | 6.12 Dépasser la borne de l'amorce en reculant · Son très court | UL |
| RM-10 | Aucune reprise sonore automatique après une interruption | P1 | EP2, EP6 | ScratchAudio, App | 6.5 Recevoir une interruption système (iPhone/iPad) · Passer en arrière-plan (iPhone/iPad) | TM, MA |
| RM-11 | La résistance ne change ni la hauteur ni la vitesse nominale sans manipulation | P1 | EP1 | ScratchCore | 6.7 Ne pas modifier la vitesse nominale | UL |
| RM-12 | Résistance élevée : scratch toujours possible dans les deux sens, arrêt au doigt fixe | P1 | EP1 | ScratchCore | 6.7 Conserver la possibilité d'arrêter le disque · Scratcher en sens inverse avec une résistance élevée | UL |
| RM-13 | La résistance ne désynchronise jamais disque affiché, son et geste (hors sillon fermé) | P1 | EP1, EP4 | ScratchCore, ScratchUI | 6.7 Modifier la résistance pendant le scratch ; 6.11 La forme d'onde suit le scratch | UL, MA |

### 3.2 RM-47 à RM-61

| ID | Résumé | Prio | Épopée | Module(s) | Section(s) Gherkin | Vérification |
|---|---|---|---|---|---|---|
| RM-47 | Tout fichier choisi ou déposé est copié dans l'app ; la source reste intacte et n'est plus nécessaire | P0 | EP3 | ScratchLibrary | 6.1 Importer un fichier WAV · Importer depuis le Finder sur Mac · Recharger un son déjà importé sans accéder à Drive · Un import ne modifie pas le fichier source ; 6.13 Déposer un fichier sur une platine | UL, MA |
| RM-48 | Aucune entrée ne référence une copie incomplète ou absente ; erreur sans altérer le son en cours | P0 | EP3 | ScratchLibrary | 6.1 Échec de copie faute d'espace · Importer un fichier incompatible · Importer un fichier corrompu ou vide | UL |
| RM-49 | Supprimer une entrée supprime la copie, jamais l'original | P1 | EP3 | ScratchLibrary | 6.13 Supprimer un son non chargé · Supprimer un son chargé sur une platine | UL |
| RM-50 | Gravure virtuelle à 33⅓ : 1 tour = 1,8 s ; vitesse = ω / (2π × 33⅓ / 60) ; 45 RPM = 1,35× | P0 | EP1 | ScratchCore | 6.2 Sélectionner 45 tours · Modifier la vitesse pendant la lecture ; 6.12 Reculer dans l'amorce | UL |
| RM-51 | Platines indépendantes ; seule la table combine leurs sorties | P0 | EP1, EP6 | ScratchCore, App | 6.8 Les platines sont indépendantes · Scratcher A pendant que B joue · Passer d'une platine à l'autre sur iPhone en portrait ; 6.4 Fader de voie | UL, TM |
| RM-52 | Gain = fader × crossfader, lissés ≤ 5 ms ; montée ≤ 1 ms en coupure franche | P0 | EP1 | ScratchCore | 6.4 Ouvrir la voie avec un déplacement minimal (cut-in) ; 6.10 Gain des voies selon la courbe · Activer le hamster | UL |
| RM-53 | Feutrine : le plateau tourne à la vitesse moteur, tenu ou non ; un toucher ne change pas l'état START/STOP | P0 | EP1 | ScratchCore | 6.9 Le plateau tourne sous le disque retenu ; 6.3 Poser le doigt sur le disque ; 6.14 Retenir et scratcher à la souris | UL |
| RM-54 | La résistance n'agit ni sur démarrage, ni sur freinage, ni sur rattrapage | P1 | EP1 | ScratchCore | 6.7 La résistance ne ralentit pas le rattrapage | UL |
| RM-55 | Sillon fermé en fin de son (et symétrique à −2 s) ; retour immédiat sans « dérouler » les tours | P1 | EP1 | ScratchCore | 6.12 Dépasser la borne de l'amorce en reculant · Atteindre la fin du son moteur actif (sillon fermé) · Revenir dans le son depuis le sillon fermé | UL |
| RM-56 | Interruption ou arrière-plan (iOS) : STOP immédiat sans rampe, état affiché, positions conservées | P1 | EP2, EP6, EP1 | ScratchAudio, App, ScratchCore | 6.5 Recevoir une interruption système (iPhone/iPad) · Passer en arrière-plan (iPhone/iPad) | TM, MA |
| RM-57 | Un son par platine ; charger sur une platine ne modifie pas l'autre ; même son possible sur A et B | P0 | EP1, EP6 | ScratchCore, App | 6.8 Charger le même son sur les deux platines ; 6.1 Importer un fichier WAV ; 6.5 Charger un deuxième fichier sur une platine active ; 6.13 Charger un son de la bibliothèque sur la platine B | UL, TM |
| RM-58 | Chaque entrée a un UUID stable et une empreinte SHA-256 | P0 ⚠ | EP3 | ScratchLibrary | 6.1 Importer un contenu déjà présent dans la bibliothèque ; 6.13 Retrouver la bibliothèque après relancement | UL |
| RM-59 | Mac : clic maintenu = doigt posé ; simultanéité par le clavier | P0 | EP5 | ScratchUI, App | 6.14 Retenir et scratcher à la souris · Couper le son au clavier pendant un scratch à la souris | TM, MA |
| RM-60 | Saisie seulement si le geste commence sur le disque ; second doigt ignoré ; toucher annulé = relâché | P0 | EP4 | ScratchUI | 6.3 Geste commencé hors du disque · Deuxième doigt sur le même disque · Toucher annulé par le système | TM, MA |
| RM-61 | Zone centrale (< 12 % du rayon) : disque retenu sans rotation, reprise sans saut en sortant | P0 | EP4, EP1 | ScratchUI, ScratchCore | 6.3 Doigt posé au centre du disque | UL, MA |

## 4. Synthèse

| | P0 | P1 | Total |
|---|---|---|---|
| SF | 23 | 21 | 44 |
| RM | 19 | 9 | 28 |
| **Total** | **42** | **30** | **72** |

Exigences marquées ⚠ (8) : SF-20, SF-74, SF-75, SF-76, SF-80, RM-58 (incohérence IC-01) ; SF-67, SF-78 (IC-02).

| Épopée principale | Nombre | Exigences |
|---|---|---|
| EP1 | 40 | SF-03 à SF-14, SF-22, SF-23, SF-64 à SF-68, SF-72, SF-77, RM-01 à RM-09, RM-11 à RM-13, RM-50 à RM-55, RM-57 |
| EP2 | 7 | SF-16, SF-18, SF-78, SF-80, SF-82, RM-10, RM-56 |
| EP3 | 10 | SF-02, SF-17, SF-24, SF-74, SF-75, SF-76, RM-47, RM-48, RM-49, RM-58 |
| EP4 | 8 | SF-01, SF-19, SF-21, SF-69, SF-70, SF-71, RM-60, RM-61 |
| EP5 | 4 | SF-73, SF-79, SF-83, RM-59 |
| EP6 | 3 | SF-15, SF-20, SF-81 |

EP6 porte en outre la recette de l'ensemble des features et le critère P0 « application fonctionnelle sur macOS, vérifiée en CI ».

## 5. Critères de recette (§7) → exigences

| Critère de recette | Prio | Exigences |
|---|---|---|
| Importer un WAV (Fichiers, Finder) et obtenir un son lisible sur la platine choisie | P0 | SF-02, SF-03, SF-79, RM-47 |
| Charger deux sons sur deux platines indépendantes | P0 | SF-64, RM-51, RM-57 |
| Démarrer et arrêter chaque moteur à 33⅓ et 45 RPM | P0 | SF-04, SF-05, RM-02, RM-50 |
| Retenir le disque sans saut de lecture, le plateau continuant de tourner | P0 | SF-06, SF-68, RM-03, RM-53 |
| Scratcher dans les deux sens, à différentes vitesses, y compris moteur arrêté | P0 | SF-05, SF-07, SF-08, SF-09, SF-77, RM-04, RM-05 |
| Relâcher le disque et retrouver la vitesse motorisée en 60 ms environ | P0 | SF-10, SF-68 (voir IC-03) |
| Scratcher et utiliser simultanément le crossfader (doigts ; souris + clavier) | P0 | SF-12, SF-19, SF-79, RM-59 |
| Coupure franche : plein niveau en 3 % de course au plus | P0 | SF-66, RM-52 |
| Application fonctionnelle sur macOS : compilation, tests et lancement en CI | P0 | Transverse (EP6, CI) |
| Résistance : comparer 10 % et 90 %, retrouver le réglage au redémarrage | P1 | SF-21, SF-22, SF-23, SF-24 |
| Pitch (pas de 0,1 %, remise à 0) et rappel d'un CUE, y compris disque tenu | P1 | SF-11, SF-13 |
| Repère et forme d'onde qui suivent le scratch ; needle drop | P1 | SF-69, SF-70, SF-71 |
| Reculer dans l'amorce et atteindre le sillon fermé sans clic | P1 | SF-14, SF-72, RM-09, RM-55 |
| Recharger depuis la bibliothèque sur A ou B, supprimer, dédoublonner | P1 | SF-74, SF-75, RM-49, RM-58 (voir IC-01) |
| Sortie USB et suivi d'un changement de périphérique | P1 | SF-16, SF-80 |
| Interruptions, arrière-plan, fichiers incorrects ou protégés, déconnexion USB sans plantage | P1 | SF-02, SF-16, SF-18, SF-81, SF-82, RM-10, RM-48, RM-56 (voir IC-01) |
| Latence geste→son mesurée et consignée (≤ 20 ms) ; tampon ≤ 256 trames | P1 | SF-78 |
| VoiceOver : toutes les commandes étiquetées | P1 | SF-83 |

## 6. Couverture Gherkin

L'épopée responsable en gras porte la majorité des scénarios de la feature ; EP6 (QA) recette toutes les features.

| Feature | Prio | Titre | Scénarios | Épopée(s) responsable(s) | Exigences vérifiées |
|---|---|---|---|---|---|
| 6.1 | P0 | Lancement et import | 14 | **EP3**, EP2, EP4, EP5, EP6 | SF-01, SF-02, SF-03, SF-20, SF-74, SF-75, SF-76, SF-79, SF-80, RM-01, RM-47, RM-48, RM-57, RM-58 |
| 6.2 | P0 | Moteur et vitesses | 8 | **EP1**, EP4 | SF-01, SF-04, SF-05, SF-10, SF-68, RM-01, RM-02, RM-03, RM-07, RM-08, RM-50 |
| 6.3 | P0 | Scratch tactile | 16 | **EP1**, EP4 | SF-05 à SF-10, SF-68, SF-77, RM-03, RM-04, RM-05, RM-07, RM-08, RM-53, RM-60, RM-61 |
| 6.4 | P0 | Crossfader et table de mixage | 6 | **EP1**, EP4 | SF-12, SF-19, SF-65, SF-66, RM-06, RM-51, RM-52 |
| 6.5 | P1 | Cycle de vie et sortie audio | 12 | **EP6**, EP2, EP3, EP4 | SF-03, SF-15, SF-16, SF-17, SF-18, SF-80, SF-81, SF-82, RM-10, RM-56, RM-57 |
| 6.6 | P1 | Pitch et CUE | 8 | **EP1**, EP4 | SF-11, SF-13, SF-64, SF-69 |
| 6.7 | P1 | Résistance et inertie tactile | 9 | **EP1**, EP4, EP3 | SF-17, SF-21 à SF-24, SF-68, RM-11, RM-12, RM-13, RM-54 |
| 6.8 | P0 | Double platine | 7 | **EP1**, EP4, EP6 | SF-19, SF-64, SF-65, RM-51, RM-57 |
| 6.9 | P0 | Feutrine, couple moteur et relâchement | 4 | **EP1**, EP4 | SF-04, SF-06, SF-10, SF-68, RM-53 |
| 6.10 | P1 | Courbe du crossfader et hamster | 3 | **EP1**, EP4, EP3 | SF-17, SF-66, SF-67, RM-52 |
| 6.11 | P1 | Repère visuel, forme d'onde et needle drop | 4 | **EP4**, EP1 | SF-69, SF-70, SF-71, RM-13 |
| 6.12 | P1 | Bornes, amorce et sillon fermé | 5 | **EP1** | SF-14, SF-72, RM-04, RM-09, RM-50, RM-55 |
| 6.13 | P1 | Bibliothèque minimale et glisser-déposer | 8 | **EP3**, EP4, EP5 | SF-15, SF-73, SF-74, SF-76, RM-47, RM-49, RM-57, RM-58 |
| 6.14 | P0 | Commandes Mac | 7 | **EP5**, EP1 | SF-06, SF-07, SF-08, SF-10, SF-79, RM-53, RM-59 |
| 6.15 | P1 | Formats et fréquences | 3 | **EP2** | SF-80 |
| 6.16 | P1 | Accessibilité | 3 | **EP5**, EP4 | SF-11, SF-83 |
| **Total** | | | **117** (62 P0, 55 P1) | | |

### Lacunes de couverture

Parties d'exigences V1 qu'aucun scénario Gherkin ne vérifie. Elles restent exigées : les stories doivent leur donner un critère d'acceptation.

- **SF-78 :** aucun scénario (seulement un critère de recette P1).
- **SF-77 :** borne de ±16×, repliement au-delà de 2× et lissage des paramètres à la fréquence audio.
- **SF-80 :** durée minimale de 50 ms.
- **SF-81 :** sur Mac, fermer la dernière fenêtre quitte l'application.
- **SF-83 :** contraste WCAG AA ; actions d'accessibilité de la résistance, des faders et du crossfader (seul le pitch a un scénario).
- **SF-70 :** rafraîchissement ≥ 60 i/s ; aperçu complet avec la tête et le CUE.
- **SF-65 :** VU-mètre par voie.
- **SF-66 :** valeurs intermédiaires de la courbe (0 < c < 1, variation monotone, 5.2).
- **SF-17 :** persistance des faders de voie et des durées moteur.
- **SF-15 :** platine « active » sans moteur (disque en mouvement ou tenu).
- **SF-74 :** affichage de l'origine du son.
- **SF-79 :** menus Platine et Table ; pitch et SET CUE / CUE au clavier.
- **RM-02 :** valeur initiale de 33⅓ RPM au premier lancement.
- **RM-56 :** arrêt « sans rampe ».

## 7. Exigences non testables automatiquement

Aspects à recetter sur appareil physique. La partie logique de ces exigences reste testée en UL ou TM (colonne « Part automatisable ») ; seul l'aspect décrit ici exige un appareil.

| ID | À recetter sur appareil | Appareils | Part automatisable |
|---|---|---|---|
| SF-78 | Latence geste→son ≤ 20 ms mesurée et consignée ; tampon réellement obtenu | iPhone, iPad, Mac de référence (Q-01 du brief) | Taille de tampon demandée (TM) |
| SF-19 | 3 contacts réels simultanés ; deux disques à deux mains | iPad, iPhone en paysage | Attribution des contacts (TM) |
| SF-16 | Interface USB (dont MPC Sample, PO-08), casque filaire et Bluetooth, débranchement, changement de périphérique à 48 kHz | iPhone, iPad, Mac + interface USB | Réaction aux notifications de route simulées (TM) |
| SF-18, RM-10, RM-56 | Interruptions réelles : appel, Siri, alarme ; veille du Mac | iPhone, iPad, Mac | Arrêt des moteurs sur notification simulée (TM) |
| SF-81 | Passage en arrière-plan et retour ; fenêtre inactive sur Mac | iPhone, iPad, Mac | Transitions d'état de l'AppModel (TM) |
| SF-06 à SF-10, SF-68, RM-08 | Sensation au doigt et à la souris, absence de discontinuité à l'écoute, « release » depuis le repère | Tous | Modèle physique et continuité du signal (UL) |
| SF-22 (PO-15) | Calibrage de la résistance (constantes de 2 à 35 ms) | iPhone, iPad | Réponse indicielle du filtre (UL) |
| SF-77 | Écoute critique : baby scratch, vitesses élevées, grésillement, repliement | Tous | Métriques de continuité et spectrales (UL) |
| SF-70 | Fluidité ≥ 60 i/s sans retard visible pendant le scratch | iPhone, iPad (120 Hz), Mac | — |
| SF-69, RM-13 | Alignement visuel du repère, du disque et du son | Tous | Calcul de l'angle (UL) |
| RM-60 | Toucher annulé par le système (notification, geste système, rotation) | iPhone, iPad | Machine d'états du geste (TM) |
| RM-61 | Zone centrale au doigt | iPhone, iPad | Géométrie (UL) |
| SF-79, RM-59 | Souris, trackpad (défilement à deux doigts, relâchement à 80 ms), clavier simultané | Mac | Mappage clavier, minuterie de 80 ms (TM) |
| SF-73 | Glisser-déposer depuis Fichiers (iPad) et depuis le Finder | iPad, Mac | Filtrage des types déposés (TM) |
| SF-02, RM-47 | Sélecteur Fichiers et iCloud Drive, fichier protégé (DRM) réel | iPhone, iPad, Mac | Copie, atomicité, erreurs (UL) |
| SF-20 | Fonctionnement en mode avion | iPhone, iPad | Rechargement sans la source (UL) |
| SF-83 | Parcours VoiceOver réel, accès clavier complet sur Mac, contraste | iPhone, iPad, Mac | Présence des libellés (TM) |
