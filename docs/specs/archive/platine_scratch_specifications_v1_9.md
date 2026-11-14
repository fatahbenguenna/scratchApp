# Platine Scratch 33 — Spécifications fonctionnelles et scénarios Gherkin

- **Version :** 1.9 — document de travail évolutif
- **Date :** 12 novembre 2026
- **Plateformes cibles :** iPhone (iOS), iPad (iPadOS)
- **Objectif :** reproduire une platine vinyle 33⅓ tours permettant de scratcher au doigt un fichier audio personnel.
- **Statut :** première base à modifier au fil des échanges ; décisions non arrêtées signalées ci-dessous.

## 1. Vision et périmètre

L'utilisateur importe un son depuis l'application **Fichiers** d'Apple, le fait jouer sur une platine motorisée virtuelle, le retient, le pousse ou le ramène en arrière. Le moteur sonore suit la position et la vitesse du disque en temps réel. Il peut couper le son rythmiquement avec un crossfader.

Le scratch n'est **pas** un effet préenregistré : il est calculé à partir du son importé.

### Inclus en V1

- Une platine virtuelle et une sortie audio.
- Import local/iCloud Drive via le sélecteur de documents d'Apple.
- Formats WAV, AIFF, MP3 et M4A non protégés (sous réserve du décodage système).
- Lecture 33⅓ RPM par défaut ; option 45 RPM.
- Commandes START, STOP, PITCH (−8 % à +8 %), CUE et crossfader.
- Manipulation multitouch : scratch sur disque et crossfader en parallèle.
- Lecture avant/arrière avec vitesse et hauteur variables.
- Affichage titre, durée, position et route audio.
- Compatibilité avec sorties audio reconnues par iOS/iPadOS, y compris USB.
- Gestion des erreurs, interruptions et changements de sortie.
- Préférences simples conservées entre lancements.

### Options reportées après la V1

- **Reverse motorisé (P2)** : sens de lecture automatique inversé avec scratch manuel conservé.
- **Crépitement vinyle (P2)** : générateur sonore autonome, activable avec volume indépendant.
- **Enregistrement du mix audio (P2)** : bouton REC de démarrage/arrêt et sauvegarde locale dans le dossier de l’application, avec gestion du stockage insuffisant.
- **Gestion automatique des pointeurs (P2)** : positions temporelles mémorisées par fichier audio, restaurées automatiquement à la réimportation, sans création de projet.
- **Enregistrement microphone et banque de sons (P2)** : capturer un son avec le micro iPhone/iPad ; réunir les prises et les fichiers déjà importés dans une bibliothèque locale de copies réelles, puis les charger comme disques à scratcher ; renommer un son directement dans la banque par appui long, sans perdre ses pointeurs.

### Hors périmètre V1

Deuxième platine, synchronisation BPM, stems en temps réel, effets complexes, export/partage avancé des prises enregistrées, intégration directe en plugin Logic Pro, contrôle MIDI externe.

## 2. Parcours nominal

1. L'utilisateur ouvre l'application.
2. La platine s'affiche, sans lecture automatique.
3. Il touche **Importer**.
4. Le sélecteur natif **Fichiers** s'ouvre.
5. Il choisit un audio compatible ; l’application en crée une copie durable dans son stockage local avant de l’ouvrir sur la platine.
6. Le titre et la durée sont affichés ; la position est au début et le moteur à l'arrêt.
7. Il touche **START** ; le plateau accélère jusqu'à sa vitesse cible et la lecture suit la rotation.
8. Il pose un doigt sur le vinyle : le plateau s'immobilise lorsque son doigt reste fixe.
9. Il pousse et tire le vinyle : le son avance et recule à la vitesse de son geste.
10. Il manipule simultanément le crossfader pour rythmer les coupures.
11. Il relâche le vinyle : si le moteur est actif, la lecture revient progressivement à la vitesse cible depuis la position atteinte.
12. Il touche **STOP** ; la rotation ralentit puis s'arrête, sans perdre sa position.

## 3. Interface utilisateur

- Disque central animé, surface tactile interactive.
- Bouton **Importer**.
- Bouton **START / STOP**.
- Sélecteur **33⅓ / 45 RPM**, réglé sur 33⅓ au démarrage initial.
- Curseur **PITCH** de −8 % à +8 %, valeur initiale 0 %.
- **Crossfader** fermé/ouvert avec gain continu intermédiaire.
- Curseur **RÉSISTANCE DU VINYLE** (léger ↔ lourd), visible directement sur l’écran principal et réglable pendant le scratch, avec valeur par défaut médiane.
- Boutons **Définir CUE** / **Rappeler CUE** (ou interaction équivalente à préciser).
- Affichage du titre, de la durée, de la position de lecture et de la sortie audio.
- Implantation adaptée à l'iPhone en portrait et à l'iPad en portrait/paysage.
- **Interfaces futures (P2 uniquement) :** interrupteur REVERSE, module Crépitement vinyle ON/OFF avec niveau 0–100 %, bouton REC et panneau de pointeurs numérotés avec pagination ; ces contrôles ne sont pas requis pour la recette V1.

## 4. Exigences fonctionnelles V1 (SF-01 à SF-24)

| ID | Exigence | Résultat attendu |
|---|---|---|
| SF-01 | Ouverture | Afficher une platine sans lecture automatique ; proposer l'import si aucun audio n'est présent. |
| SF-02 | Import audio et copie | Ouvrir Fichiers et accepter les fichiers WAV, AIFF, MP3 et M4A décodables, non protégés ; copier le fichier dans le dossier local de l’application, sans modifier la source. Le chargement ultérieur repose sur cette copie et non sur un signet ou un chemin externe. En cas d’échec de copie ou d’espace insuffisant, signaler l’erreur et ne pas ajouter de fichier incomplet. |
| SF-03 | Initialisation | Après import : titre et durée affichés, position au début, moteur arrêté. |
| SF-04 | START | Accélérer progressivement jusqu'à la vitesse cible ; l'audio suit la vitesse réelle. |
| SF-05 | STOP | Décélérer jusqu'à zéro et conserver la position audio ; le scratch manuel reste disponible une fois le moteur arrêté. |
| SF-06 | Prise en main | Le geste sur la surface du disque prend la priorité sur son moteur ; un doigt immobile retient le plateau. |
| SF-07 | Scratch avant | Une rotation manuelle vers l'avant avance dans l'audio. |
| SF-08 | Scratch arrière | Une rotation manuelle inverse lit l'audio à l'envers. |
| SF-09 | Vitesse du geste | La vitesse/hauteur de lecture suivent le mouvement du disque avec interpolation audio adaptée. |
| SF-10 | Relâchement | Moteur actif : reprise progressive depuis la position actuelle ; moteur arrêté : immobilité. |
| SF-11 | Pitch | Modifier la vitesse nominale de −8 % à +8 % en modifiant aussi la hauteur. |
| SF-12 | Crossfader | Modifier uniquement le gain de sortie, sans altérer la position de lecture. |
| SF-13 | CUE | Définir et rappeler une position ; rappel sans CUE : retour au début. |
| SF-14 | Limites du fichier | Bloquer la position au début/à la fin ; aucune lecture hors limites ni clic anormal. |
| SF-15 | Remplacement | Confirmer si un autre fichier est choisi pendant la lecture ; remettre la platine à l'état initial après validation. |
| SF-16 | Sortie audio | Utiliser la route audio iOS/iPadOS active, notamment une interface USB compatible. |
| SF-17 | Préférences | Conserver RPM, pitch et crossfader ; ne jamais relancer automatiquement l'audio. |
| SF-18 | Interruptions | Suspendre la lecture, conserver la position et demander une reprise manuelle. |
| SF-19 | Multitouch | Permettre scratch et crossfader simultanés, sans perte de contrôle. |
| SF-20 | Absence de réseau | Permettre un fonctionnement hors ligne pour les fichiers accessibles localement. |
| SF-21 | Résistance réglable | Proposer sur la platine un curseur « Résistance du vinyle » de 0 à 100 %, de léger à lourd ; la valeur est ajustable en temps réel. |
| SF-22 | Effet de la résistance | À geste tactile identique, une résistance élevée atténue les accélérations et variations de vitesse excessives ; une résistance faible permet une réponse plus directe. Le moteur sonore suit le mouvement simulé du disque et non directement celui du doigt. |
| SF-23 | Continuité du réglage | Une modification de résistance ne saute pas la position de lecture et ne provoque ni clic audio ni inversion inattendue ; le contrôle du disque reste prioritaire sur le moteur. |
| SF-24 | Préférence de résistance | Mémoriser la dernière valeur de résistance pour les lancements suivants, sans déclencher de lecture automatique. |



## 5. Règles métier V1 (RM-01 à RM-13)

- **RM-01 :** sans fichier audio chargé, aucun son n’est émis dans la V1.
- **RM-02 :** la vitesse nominale initiale est 33⅓ RPM.
- **RM-03 :** le toucher manuel est prioritaire sur l'entraînement moteur.
- **RM-04 :** le déplacement angulaire détermine le déplacement temporel dans le fichier.
- **RM-05 :** une rotation inverse produit une lecture inverse réelle, et non un bruit de scratch préenregistré.
- **RM-06 :** le crossfader ne change pas la position de lecture.
- **RM-07 :** le relâchement n'entraîne une reprise motorisée que si le moteur est actif.
- **RM-08 :** les variations de vitesse et de gain évitent autant que possible les discontinuités audibles.
- **RM-09 :** le lecteur ne dépasse jamais les bornes du fichier audio.
- **RM-10 :** aucune interruption système ne provoque une reprise sonore automatique.
- **RM-11 :** la résistance change la réponse dynamique du disque virtuel au geste, pas la hauteur ou la vitesse nominale du moteur en l’absence de manipulation.
- **RM-12 :** une valeur élevée ne doit pas rendre le scratch impossible : l’utilisateur doit toujours pouvoir déplacer le disque dans les deux sens et l’immobiliser en maintenant son doigt fixe.
- **RM-13 :** les variations de résistance ne doivent jamais désynchroniser position visuelle, position audio et scratch.
- **RM-43 :** tout fichier sélectionné via Fichiers est copié dans le stockage propre à l’application ; sa source d’origine reste inchangée et n’est pas nécessaire pour les rechargements suivants.
- **RM-44 :** aucune fiche de bibliothèque ne peut référencer une copie locale incomplète ou absente ; une erreur de stockage est signalée sans altérer le son en cours.
- **RM-45 :** la suppression d’une entrée de la bibliothèque locale, lorsqu’elle sera disponible, concerne sa copie dans l’application, jamais le fichier original sur Drive ou dans Fichiers.



### Précision de conception — Sensibilité et inertie

Le réglage demandé est **la sensation de lourdeur du disque** et non un simple ralentissement graphique. Il doit moduler la réactivité du disque virtuel aux accélérations rapides du doigt et la réponse sonore correspondante. Une implémentation plausible utilise un filtre dynamique ou un modèle de couple/inertie sur la vitesse angulaire commandée ; son calibrage sera validé sur appareil physique. Le contact fixe doit rester capable d’arrêter le disque. La latence perçue doit rester faible.

Un éventuel **gain de déplacement tactile** (nombre de degrés de rotation du vinyle pour un geste donné) est un paramètre distinct et n’est pas retenu comme réglage supplémentaire en V1.1.


## 6. Scénarios Gherkin — classés par priorité

**P0 — Critique :** parcours minimal nécessaire pour charger un son, faire tourner le disque, scratcher et couper le son.

**P1 — Important :** compléments de la V1 (robustesse, périphériques, pitch/CUE, sensation tactile).

**P2 — Option future :** fonctionnalités exclues de la recette V1, spécifiées en fin de document.

### 6.1 [P0] Lancement et import

```gherkin
Feature: Lancement et importation d'un fichier audio
  En tant qu'utilisateur
  Je veux charger un fichier audio depuis Fichiers
  Afin de le scratcher sur une platine virtuelle

  Scenario: Premier lancement sans fichier
    Given l'application n'a aucun fichier chargé
    When je lance l'application
    Then la platine est affichée
    And le disque est immobile
    And aucun son n'est joué
    And le bouton "Importer" est disponible

  Scenario: Importer un fichier WAV
    Given la platine est affichée
    When j'appuie sur "Importer"
    Then le sélecteur Fichiers d'Apple s'ouvre
    When je sélectionne un fichier WAV valide
    Then une copie complète du fichier est créée dans le dossier de l’application
    And le fichier est chargé depuis cette copie
    And son titre et sa durée sont affichés
    And la position de lecture est à zéro
    And le moteur est arrêté

  Scenario Outline: Importer un format audio compatible
    Given le sélecteur Fichiers est ouvert
    When je sélectionne un fichier "<format>" valide
    Then le fichier est chargé
    And la platine est prête à être utilisée

    Examples:
      | format |
      | WAV    |
      | AIFF   |
      | MP3    |
      | M4A    |

  Scenario: Recharger un son déjà importé sans accéder à Drive
    Given un fichier audio a été importé et copié dans le dossier de l'application
    And sa source d'origine est devenue inaccessible
    When je sélectionne le son dans la bibliothèque locale disponible
    Then le son est chargé depuis sa copie locale
    And aucune connexion à Drive n'est nécessaire

  Scenario: Échec de copie faute d'espace
    Given le stockage libre est insuffisant pour copier le fichier sélectionné
    When je tente de l'importer depuis Fichiers
    Then un message « Espace de stockage insuffisant » est affiché
    And aucune copie incomplète n'est conservée comme son utilisable
    And le fichier précédemment chargé reste disponible

  Scenario: Un import ne modifie pas le fichier source
    Given un fichier valide existe dans iCloud Drive
    When je l'importe dans l'application
    Then une copie distincte est stockée dans le dossier de l'application
    And le fichier dans iCloud Drive reste inchangé

  Scenario: Annuler l'importation
    Given le sélecteur Fichiers est ouvert
    When j'annule la sélection
    Then je reviens à la platine
    And le fichier précédemment chargé est conservé

  Scenario: Importer un fichier incompatible
    Given le sélecteur Fichiers est ouvert
    When je sélectionne un fichier non décodable
    Then un message d'erreur est affiché
    And aucun fichier invalide n'est chargé
    And l'application reste utilisable
```

### 6.2 [P0] Moteur et vitesses

```gherkin
Feature: Contrôle du moteur de la platine
  En tant que DJ
  Je veux démarrer et arrêter le moteur
  Afin de reproduire une platine vinyle

  Background:
    Given un fichier audio valide est chargé
    And le disque est immobile
    And le pitch est réglé à 0 %

  Scenario: Démarrer la platine à 33 tours
    Given la vitesse sélectionnée est 33⅓ RPM
    When j'appuie sur "START"
    Then le moteur démarre
    And le disque accélère progressivement
    And il atteint 33⅓ tours par minute
    And l'audio suit la rotation du disque

  Scenario: Arrêter la platine
    Given le moteur tourne à 33⅓ RPM
    When j'appuie sur "STOP"
    Then le disque ralentit progressivement
    And le son ralentit avec le disque
    And le disque finit par s'immobiliser
    And la position audio est conservée

  Scenario: Sélectionner 45 tours
    Given le moteur est arrêté
    When je sélectionne "45 RPM"
    And j'appuie sur "START"
    Then le disque accélère jusqu'à 45 RPM
    And la lecture utilise cette vitesse nominale

  Scenario: Modifier la vitesse pendant la lecture
    Given le moteur tourne à 33⅓ RPM
    When je sélectionne "45 RPM"
    Then le moteur rejoint progressivement 45 RPM
    And la lecture suit la nouvelle vitesse
    And la position audio reste continue

  Scenario: Démarrer sans fichier
    Given aucun fichier audio n'est chargé
    When j'appuie sur "START"
    Then aucun son n'est joué
    And l'application propose d'importer un fichier
```

### 6.3 [P0] Scratch tactile

```gherkin
Feature: Manipulation tactile du vinyle
  En tant que DJ
  Je veux manipuler le disque avec mon doigt
  Afin de produire des scratchs naturels

  Background:
    Given un fichier audio est chargé
    And le moteur tourne à 33⅓ RPM
    And le crossfader est ouvert

  Scenario: Poser le doigt sur le disque
    When je pose un doigt sur la surface du vinyle
    And je maintiens mon doigt immobile
    Then le disque cesse de tourner
    And la lecture audio est suspendue
    And la position audio reste stable

  Scenario: Pousser le disque vers l'avant
    Given je maintiens le disque avec mon doigt
    When je tourne le disque dans le sens normal
    Then la position audio avance
    And le son est lu vers l'avant
    And sa vitesse suit mon mouvement

  Scenario: Faire reculer le disque
    Given je maintiens le disque avec mon doigt
    When je tourne le disque en sens inverse
    Then la position audio recule
    And le son est lu à l'envers
    And sa vitesse suit mon mouvement

  Scenario: Faire un scratch avant-arrière
    Given je maintiens le disque avec mon doigt
    When je pousse le disque vers l'avant
    And je le ramène vers l'arrière
    Then le son avance puis recule
    And aucune rupture audio anormale ne se produit

  Scenario: Varier la vitesse du scratch
    Given je manipule le disque manuellement
    When j'augmente la vitesse de mon geste
    Then la vitesse de lecture augmente
    And la hauteur du son varie avec la vitesse

  Scenario: Maintenir un disque immobile
    Given je maintiens le disque avec mon doigt
    When je ne déplace plus mon doigt
    Then la vitesse de lecture est nulle
    And aucun nouvel échantillon n'est parcouru

  Scenario: Relâcher le disque moteur actif
    Given je maintiens le disque immobile
    When je retire mon doigt
    Then le moteur reprend le contrôle
    And le disque accélère progressivement
    And la lecture reprend depuis la position actuelle
    And la vitesse rejoint 33⅓ RPM

  Scenario: Scratcher avec le moteur arrêté
    Given un fichier audio est chargé
    And le moteur est complètement arrêté après STOP
    When je pousse le disque manuellement vers l'avant
    Then le son est lu vers l'avant à la vitesse de mon geste
    When je tire le disque manuellement vers l'arrière
    Then le son est lu à l'envers à la vitesse de mon geste
    And le moteur reste arrêté

  Scenario: Relâcher le disque moteur arrêté
    Given le moteur est arrêté
    And je manipule le disque manuellement
    When je retire mon doigt
    Then le disque reste immobile
    And aucune lecture automatique ne démarre

  Scenario: Dépasser le début du fichier en reculant
    Given la lecture est à la position initiale
    When je tourne le disque vers l'arrière
    Then la position reste au début du fichier
    And aucun échantillon hors limites n'est lu
    And aucun bruit parasite n'est produit
```

### 6.4 [P0] Crossfader

```gherkin
Feature: Contrôle du crossfader
  En tant que DJ
  Je veux couper et rétablir rapidement le son
  Afin d'exécuter des scratchs rythmiques

  Background:
    Given un fichier audio est chargé
    And le moteur est actif

  Scenario: Fermer complètement le crossfader
    Given le crossfader est ouvert
    When je le déplace en position fermée
    Then le niveau de sortie devient silencieux
    And la lecture continue à sa position normale

  Scenario: Ouvrir le crossfader
    Given le crossfader est fermé
    When je le déplace en position ouverte
    Then le son redevient audible
    And la lecture n'est pas repositionnée

  Scenario: Scratch avec coupure rythmique
    Given mon premier doigt contrôle le vinyle
    And mon deuxième doigt contrôle le crossfader
    When j'effectue un scratch avant-arrière
    And j'ouvre et ferme plusieurs fois le crossfader
    Then le son n'est audible que pendant les ouvertures
    And les deux commandes fonctionnent simultanément
    And le disque reste contrôlé par mon premier doigt

  Scenario: Crossfader en position intermédiaire
    Given un signal audio est lu
    When je place le crossfader à 50 %
    Then le niveau de sortie suit la courbe de gain définie
    And la position de lecture est inchangée
```

### 6.5 [P1] Cycle de vie et sortie audio

```gherkin
Feature: Cycle de vie et sortie audio

  Scenario: Charger un deuxième fichier
    Given un fichier est chargé et en cours de lecture
    When j'appuie sur "Importer"
    And je sélectionne un nouveau fichier
    Then une confirmation de remplacement apparaît
    When je confirme
    Then l'ancien fichier est déchargé
    And le nouveau fichier est chargé
    And le moteur est arrêté
    And la position audio est à zéro

  Scenario: Refuser le remplacement
    Given un fichier est en cours de lecture
    When je sélectionne un autre fichier
    And je refuse le remplacement
    Then le fichier initial reste chargé
    And son état de lecture est conservé

  Scenario: Recevoir une interruption système
    Given le moteur tourne
    When une interruption audio système survient
    Then la lecture est suspendue
    And la position est conservée
    When l'interruption se termine
    Then la reprise nécessite une action utilisateur

  Scenario: Brancher une interface audio USB
    Given une interface audio USB compatible est connectée
    And elle est sélectionnée comme sortie par le système
    When je lance la lecture
    Then le son est envoyé à cette interface
    And le scratch reste opérationnel

  Scenario: Perdre le périphérique audio
    Given la lecture utilise une interface USB
    When l'interface est déconnectée
    Then l'application ne plante pas
    And elle suit la nouvelle route audio du système
    And elle suspend la lecture si nécessaire

  Scenario: Restaurer les préférences
    Given j'ai sélectionné 45 RPM
    And j'ai réglé le pitch à +3 %
    When je ferme puis relance l'application
    Then la vitesse sélectionnée est 45 RPM
    And le pitch est à +3 %
    And aucune lecture automatique ne démarre
```

### 6.6 [P1] Pitch et CUE

```gherkin
Feature: Réglage du pitch et des points CUE
  En tant que DJ
  Je veux régler la vitesse et retrouver une position
  Afin de préparer mes scratchs

  Scenario Outline: Modifier le pitch
    Given le moteur tourne à 33⅓ RPM
    When je règle le pitch sur <pitch> %
    Then la vitesse cible est <vitesse> RPM
    And la hauteur sonore suit la variation de vitesse

    Examples:
      | pitch | vitesse |
      | -8    | 30.67   |
      | 0     | 33.33   |
      | 8     | 36.00   |

  Scenario: Mémoriser un point CUE
    Given un fichier audio est chargé
    And la position de lecture est à 12 secondes
    When je définis un point CUE
    Then la position de 12 secondes est mémorisée

  Scenario: Revenir au point CUE
    Given un point CUE existe à 12 secondes
    And la lecture est à 30 secondes
    When j'appuie sur "CUE"
    Then la lecture revient à 12 secondes
    And l'état du moteur est conservé

  Scenario: Rappeler CUE sans point enregistré
    Given aucun point CUE n'est défini
    When j'appuie sur "CUE"
    Then la lecture revient au début du fichier
```

### 6.7 [P1] Résistance et inertie tactile réglables

```gherkin
Feature: Réglage de la résistance du vinyle
  En tant qu'utilisateur
  Je veux régler la lourdeur du disque depuis la platine
  Afin de retrouver une sensation de scratch proche d'un vrai vinyle

  Background:
    Given un fichier audio valide est chargé
    And le crossfader est ouvert
    And le moteur tourne à 33⅓ RPM

  Scenario: Afficher le réglage sur l'interface principale
    When j'affiche la platine
    Then le curseur "Résistance du vinyle" est visible
    And sa valeur est comprise entre 0 et 100 %
    And la valeur par défaut est 50 % au premier lancement

  Scenario: Réduire la résistance
    Given la résistance est réglée à 80 %
    When je règle la résistance à 10 %
    And j'effectue un geste rapide vers l'avant
    Then le disque simulé répond plus directement au geste qu'à 80 %
    And le son suit la vitesse du disque simulé

  Scenario: Augmenter la résistance
    Given la résistance est réglée à 10 %
    When je règle la résistance à 90 %
    And j'effectue le même geste rapide vers l'avant
    Then les accélérations du disque simulé sont plus amorties qu'à 10 %
    And la vitesse sonore suit la vitesse du disque simulé
    And la position audio reste continue

  Scenario: Conserver la possibilité d'arrêter le disque
    Given la résistance est réglée à 100 %
    When je pose un doigt immobile sur le disque
    Then le disque s'immobilise
    And l'audio n'avance plus

  Scenario: Scratcher en sens inverse avec une résistance élevée
    Given la résistance est réglée à 90 %
    When je manipule le disque vers l'arrière
    Then le disque finit par tourner en sens inverse
    And l'audio est lu en sens inverse
    And aucune inversion inattendue ne se produit

  Scenario: Modifier la résistance pendant le scratch
    Given je scratche le disque
    When je modifie la résistance avec un autre doigt
    Then la nouvelle résistance est appliquée sans saut de position
    And aucun clic audio anormal n'est produit
    And je conserve le contrôle du disque

  Scenario: Ne pas modifier la vitesse nominale
    Given la résistance est réglée à 100 %
    And je ne touche pas le disque
    When le moteur atteint son régime nominal
    Then la vitesse reste égale à 33⅓ RPM avec un pitch à 0 %

  Scenario: Restaurer le réglage mémorisé
    Given j'ai réglé la résistance à 75 %
    When je quitte puis relance l'application
    Then la résistance affichée est 75 %
    And aucune lecture ne démarre automatiquement
```

## 7. Critères de recette V1 (P0 puis P1)

- [ ] Importer un WAV depuis Fichiers et obtenir un son lisible.
- [ ] Démarrer/arrêter le moteur à 33⅓ RPM.
- [ ] Bloquer le disque au toucher sans saut de lecture.
- [ ] Scratcher dans les deux sens, à différentes vitesses, y compris après STOP et avec le moteur entièrement arrêté.
- [ ] Relâcher le disque et retrouver la vitesse motorisée.
- [ ] Scratcher et utiliser simultanément le crossfader.
- [ ] Ajuster la résistance du vinyle depuis l’interface, comparer les réactions à 10 % et 90 %, et retrouver le réglage au redémarrage.
- [ ] Modifier le pitch et rappeler un point CUE.
- [ ] Émettre le son sur une sortie audio USB compatible.
- [ ] Gérer interruptions, fichiers incorrects et déconnexion USB sans plantage.

## 8. Points ouverts à préciser

- **PO-01 :** comportement du plateau lorsque aucun fichier n'est chargé (animation possible ou immobilité forcée).
- **PO-02 :** choix ergonomique du crossfader sur une platine unique : bouton de coupure ou curseur gauche-droite avec une seule source.
- **PO-03 :** courbes et durées d'accélération/décélération du moteur.
- **PO-04 :** inertie au relâchement, gestion du geste et de l'angle tactile.
- **PO-05 :** comportement souhaité en fin de sample (arrêt, boucle, silence tout en tournant).
- **PO-06 :** ergonomie des points CUE et de leurs raccourcis.
- **PO-07 :** contraintes cibles de latence audio et tactile, à quantifier après prototype.
- **PO-08 :** compatibilité audio USB exacte avec MPC Sample et méthode d'enregistrement dans Logic Pro, à tester sur matériel.
- **PO-09 :** fonctionnement en arrière-plan et stratégie de session audio.
- **PO-10 :** design graphique de la platine et disposition des commandes sur iPhone/iPad.
- **PO-11 [P2] :** calibrage sonore du souffle, densité des micro-craquements et éventuel recours à un générateur procédural ou à des ressources embarquées.

## 9. Journal des modifications

| Version | Date | Modification |
|---|---|---|
| 1.0 | 2026-11-12 | Première consolidation des spécifications fonctionnelles et des scénarios Gherkin de base. |
| 1.1 | 2026-11-12 | Ajout du curseur de résistance du vinyle (SF-21 à SF-24), règles RM-11 à RM-13, scénarios Gherkin 6.7 et critère de recette. |
| 1.2 | 2026-11-12 | Ajout de la lecture inversée avec scratch bidirectionnel (SF-25 à SF-28), règles RM-14 à RM-17 et scénarios Gherkin (désormais section 10.1). |
| 1.3 | 2026-11-12 | Ajout de l'effet autonome Crépitement vinyle (SF-29 à SF-34), règles RM-18 à RM-22 et scénarios Gherkin (désormais section 10.2) ; volume indépendant du disque et du crossfader. |
| 1.4 | 2026-11-12 | Classement des scénarios Gherkin P0/P1 et transfert de Reverse et Crépitement en options futures P2, en fin de document. |
| 1.5 | 2026-11-12 | Ajout de l’enregistrement local (SF-35 à SF-41), règles RM-23 à RM-28 et scénarios Gherkin 10.3 ; conservation en option future P2. |
| 1.6 | 2026-11-12 | Gestion automatique des pointeurs (SF-42 à SF-50, RM-29 à RM-35, Gherkin 10.4) en P2 ; clarification du scratch moteur arrêté en P0. |
| 1.7 | 2026-11-12 | Ajout option P2 « Enregistrement microphone et banque de sons » (SF-51 à SF-59, RM-36 à RM-42, scénarios 10.5), distincte de l’enregistrement du mix ; critères de recette optionnels mis à jour. |
| 1.8 | 2026-11-12 | Décision : copie locale systématique des imports, bibliothèque physique unifiée avec les prises micro (interface P2) ; pas de signets ni de liens externes ; Gherkin sur copie, lecture hors ligne, stockage et suppression. |
| 1.9 | 2026-11-12 | Nommage des prises micro et conservation des noms importés ; menu contextuel de renommage dans la banque (SF-60 à SF-63, RM-43 à RM-46, huit scénarios Gherkin) ; pointeurs préservés par identifiant stable. |

> Les prochains ajouts et corrections devront garder les identifiants SF, RM et PO stables, sauf refonte explicite.



---

## 10. Options futures — priorité P2 (hors V1)

Ces fonctionnalités sont **documentées mais non exigées** pour la première version. Leur développement et leur recette seront planifiés ultérieurement. Les identifiants SF et RM d'origine sont conservés.

### 10.1 Reverse motorisé — P2

**Interface future :** interrupteur REVERSE ON/OFF. La lecture automatique peut aller en sens inverse sans supprimer le scratch tactile bidirectionnel ni les réglages existants.

**Exigences SF-25 à SF-28 :**

| ID | Exigence | Résultat attendu |
|---|---|---|
| SF-25 | Lecture inversée | Afficher un interrupteur « Lecture inversée » (désactivé par défaut) sur l’interface principale ; en mode actif, le moteur entraîne la lecture et l’animation en sens inverse à la vitesse nominale sélectionnée (33⅓ ou 45 RPM, pitch inclus). |
| SF-26 | Scratch pendant le reverse | En mode lecture inversée, le toucher garde la priorité sur le moteur : le déplacement du doigt produit une lecture selon le sens réel de rotation imposé, vers l’avant ou l’arrière, indépendamment du sens de lecture automatique. |
| SF-27 | Reprise du moteur inversé | Après relâchement du disque, si le moteur est actif, la lecture rejoint progressivement sa vitesse nominale inversée depuis sa position actuelle, sans saut audio. |
| SF-28 | Bascule de sens | Modifier l’option pendant la lecture provoque une transition de vitesse progressive jusqu’au sens demandé, sans repositionner le fichier ni déclencher de clic anormal. Moteur arrêté, l’option n’entraîne pas de lecture. |

**Règles métier RM-14 à RM-17 :**

- **RM-14 :** en lecture inversée, le sens de lecture automatique est négatif ; la vitesse nominale reste la valeur absolue définie par RPM et pitch.
- **RM-15 :** la lecture inversée ne renverse pas l’interprétation du toucher : pousser le disque dans le sens horaire de lecture normale fait avancer l’audio ; le tirer dans le sens opposé fait reculer l’audio.
- **RM-16 :** la résistance du vinyle s’applique également en lecture inversée, avec les mêmes garanties de continuité.
- **RM-17 :** aux bornes du fichier, aucun accès audio hors limites n’est autorisé ; le comportement exact de reprise/boucle reste traité au point PO-05.

**Scénarios Gherkin (P2) :**

```gherkin
Feature: Lecture inversée avec scratch tactile
  En tant que DJ
  Je veux lire mon fichier à l'envers tout en scratchant
  Afin de manipuler librement un son en reverse

  Background:
    Given un fichier audio valide est chargé
    And la position audio est située entre le début et la fin du fichier
    And la platine est réglée sur 33⅓ RPM

  Scenario: Afficher et activer la lecture inversée
    Given la lecture inversée est désactivée
    When j'active l'option "Lecture inversée"
    Then l'option apparaît comme activée
    And le moteur utilise le sens inverse à son prochain démarrage

  Scenario: Lire automatiquement le fichier en sens inverse
    Given la lecture inversée est activée
    And le moteur est arrêté
    When j'appuie sur "START"
    Then le plateau accélère progressivement en sens inverse
    And la position de lecture recule à vitesse nominale
    And le son entendu correspond au fichier lu à l'envers

  Scenario: Scratcher en avant pendant la lecture inversée
    Given le moteur tourne en sens inverse
    When je pose le doigt sur le disque
    And je le fais tourner vers l'avant
    Then le son est lu vers l'avant selon la rotation imposée
    And la position avance sans saut

  Scenario: Scratcher en arrière pendant la lecture inversée
    Given le moteur tourne en sens inverse
    When je pose le doigt sur le disque
    And je le fais tourner vers l'arrière
    Then le son est lu vers l'arrière selon la rotation imposée
    And la position recule sans saut

  Scenario: Relâcher le disque après un scratch en reverse
    Given le moteur est actif en lecture inversée
    And je suis en train de scratcher dans un sens quelconque
    When je relâche le disque
    Then le moteur reprend progressivement le contrôle
    And la lecture rejoint la vitesse nominale en sens inverse
    And la position audio reste continue

  Scenario: Désactiver le reverse pendant la lecture
    Given le moteur tourne en lecture inversée
    When je désactive "Lecture inversée"
    Then la rotation rejoint progressivement le sens normal
    And le fichier n'est pas repositionné
    And aucun clic audio anormal n'est produit

  Scenario: Utiliser la résistance en lecture inversée
    Given la lecture inversée est activée
    And la résistance du vinyle est réglée à 90 %
    When je réalise un scratch avant-arrière
    Then la résistance amortit les mouvements selon le réglage
    And les deux directions de scratch restent possibles

  Scenario: Activer le reverse avec moteur arrêté
    Given le moteur est arrêté
    When je modifie "Lecture inversée"
    Then aucune lecture ne commence automatiquement
    And le sens choisi est appliqué au prochain démarrage
```

### 10.2 Crépitement vinyle — P2

**Interface future :** interrupteur ON/OFF et volume propre 0–100 %. Souffle et micro-craquements générés sans import de fichier et indépendamment du crossfader.

**Exigences SF-29 à SF-34 :**

| ID | Exigence | Résultat attendu |
|---|---|---|
| SF-29 | Activation du crépitement | Afficher sur l’interface principale un interrupteur « Crépitement vinyle » ON/OFF, désactivé par défaut ; l'effet doit être intégré et ne requiert aucun fichier importé. |
| SF-30 | Génération sonore intégrée | Fournir un bruit de surface de vinyle crédible, composé d’un souffle discret (« shhhh ») et de micro-crépitements non périodiques. Solution privilégiée : génération procédurale ; alternative admise : ressources audio embarquées dans l’application, avec bouclage inaudible et variation pour éviter une répétition reconnaissable. Aucun téléchargement ni son externe requis. |
| SF-31 | Niveau indépendant | Proposer un curseur de volume du crépitement de 0 à 100 %, indépendant du volume du fichier chargé, de la position du disque et du crossfader. Le volume matériel/système final reste applicable au mixage complet. |
| SF-32 | Persistance pendant le scratch | Lorsque l’effet est activé, le crépitement continue pendant la lecture normale, inversée, le scratch avant/arrière, la retenue du disque et l’arrêt du moteur, y compris sans fichier chargé, tant que la session audio de l’application est active. |
| SF-33 | Activation sans artefacts | L'activation, la désactivation et les variations de niveau sont progressives pour éviter les clics numériques ; elles ne modifient ni le fichier audio ni sa position ou sa vitesse. |
| SF-34 | Préférences de crépitement | Mémoriser l’activation et le volume de l’effet pour la session suivante ; au relancement, la sortie audio reste silencieuse jusqu’à une action explicite de l’utilisateur, y compris si l’effet était auparavant activé. |

**Règles métier RM-18 à RM-22 :**

- **RM-18 :** le signal de crépitement est produit par une voie audio distincte puis mélangé à la voie du fichier ; le crossfader n'agit que sur la voie du fichier.
- **RM-19 :** le réglage de crépitement n'affecte pas le volume, la hauteur, le sens ou la position du fichier ; le réglage de volume du fichier n'affecte pas le crépitement.
- **RM-20 :** l’effet ne dépend pas de la vitesse de rotation du disque : le souffle ne s'arrête pas lorsque le doigt retient le vinyle ou lorsque le moteur est arrêté.
- **RM-21 :** volume de crépitement à 0 % ou effet OFF signifie absence du signal d'effet à la sortie, sans modifier la lecture du fichier.
- **RM-22 :** l'interruption audio iOS/iPadOS interrompt aussi le crépitement ; aucune reprise spontanée après une interruption ni au lancement de l'application.

**Scénarios Gherkin (P2) :**

```gherkin
Feature: Effet de crépitement vinyle indépendant
  En tant qu'utilisateur
  Je veux ajouter un bruit de surface de disque vinyle
  Afin de retrouver une ambiance analogique sans charger un sample d'effet

  Background:
    Given l'application est ouverte au premier plan
    And la sortie audio système est disponible

  Scenario: Afficher les contrôles de l'effet
    When j'affiche la platine
    Then un interrupteur "Crépitement vinyle" est visible
    And un curseur de volume de l'effet de 0 à 100 % est visible
    And l'effet est désactivé par défaut au premier lancement

  Scenario: Activer l'effet sans importer de son
    Given aucun fichier audio n'est chargé
    When j'active "Crépitement vinyle"
    Then un souffle vinyle et des micro-crépitements sont audibles
    And aucun fichier audio n'est demandé

  Scenario: Ajuster uniquement le volume du crépitement
    Given un fichier est en cours de lecture
    And l'effet est activé
    When je réduis le volume du crépitement de 70 % à 20 %
    Then le crépitement devient moins fort
    And le volume du fichier reste inchangé
    And la position de lecture reste inchangée

  Scenario: Couper le son du disque avec le crossfader
    Given un fichier est en cours de lecture
    And l'effet est activé à 40 %
    When je ferme le crossfader
    Then le son du fichier devient silencieux
    And le crépitement reste audible à son niveau réglé

  Scenario: Maintenir l'effet pendant le scratch et le reverse
    Given l'effet est activé à 40 %
    And un fichier audio est chargé
    When j'active "Lecture inversée"
    And je fais un scratch avant puis arrière
    Then le fichier réagit à mon geste et au mode reverse
    And le crépitement continue sans changer de volume

  Scenario: Maintenir l'effet à l'arrêt du plateau
    Given l'effet est activé
    When j'arrête le moteur
    And je maintiens le disque immobile
    Then le crépitement continue
    And aucune lecture du fichier n'est imposée par l'effet

  Scenario: Ramener le crépitement à zéro
    Given l'effet est activé
    When je règle le volume de l'effet à 0 %
    Then le crépitement est inaudible
    And l'effet ne coupe pas la sortie du fichier

  Scenario: Désactiver l'effet
    Given le crépitement est audible
    When je désactive "Crépitement vinyle"
    Then le crépitement disparaît sans clic numérique anormal
    And la lecture du fichier continue sans interruption

  Scenario: Conserver les préférences sans lecture automatique
    Given j'ai activé le crépitement à 35 %
    When je ferme puis relance l'application
    Then le réglage de 35 % est conservé
    And l'interrupteur affiche l'état précédemment choisi
    But aucun son ne démarre avant une nouvelle action explicite

  Scenario: Interruption audio système
    Given le crépitement est audible
    When une interruption audio système survient
    Then le crépitement et le fichier éventuel sont suspendus
    And ils ne reprennent pas automatiquement à la fin de l'interruption

  Scenario: Le motif sonore ne forme pas une boucle perceptible
    Given le crépitement est activé
    When je l'écoute en continu pendant plusieurs minutes
    Then aucun raccord de boucle audible ne se produit
    And la variation des micro-crépitements n'est pas strictement répétitive
```

### 10.3 Enregistrement audio local — P2

**Interface future :** bouton **REC** accessible sur la platine, avec état visuel « Enregistrement » et compteur de durée. Un appui démarre immédiatement la capture, un second appui la termine et sauvegarde le résultat. La source capturée est le **mix de sortie de la platine**, comprenant le sample et les manipulations (scratch, crossfader, pitch), ainsi que les effets activés lorsque ceux-ci seront implémentés. Les sons provenant d'autres applications ou du microphone ne sont pas enregistrés.

**Exigences SF-35 à SF-41 :**

| ID | Exigence | Résultat attendu |
|---|---|---|
| SF-35 | Bouton REC | Un premier appui sur REC commence immédiatement l'enregistrement du mix audio de l'application ; le bouton change d'état et le compteur démarre. Aucun écran de configuration préalable. |
| SF-36 | Arrêt et finalisation | Un second appui sur REC arrête la capture et finalise un fichier audio exploitable ; une confirmation affiche son nom et son emplacement. Le disque peut continuer à jouer. |
| SF-37 | Dossier local par défaut | Enregistrer dans le dossier **Enregistrements** de l'espace Documents de l'application, sur l'iPhone/iPad courant ; le dossier est créé si nécessaire et rendu accessible dans **Fichiers > Sur mon iPhone / Sur mon iPad > [Nom de l'application]**, sous réserve de l'activation du partage de documents iOS. Aucun export manuel n'est nécessaire pour la sauvegarde locale. |
| SF-38 | Nom et format | Attribuer automatiquement un nom unique horodaté, par exemple `scratch_2026-11-12_102400.wav`. Format WAV PCM par défaut ; ses paramètres (fréquence/bit depth) seront précisés dans les spécifications techniques. |
| SF-39 | Stockage insuffisant | Contrôler la capacité disponible avant de commencer lorsque possible, surveiller les erreurs d'écriture pendant la capture, arrêter proprement si l'espace est épuisé, informer l'utilisateur et préserver une prise partielle récupérable si techniquement possible. Ne jamais signaler une sauvegarde réussie si elle a échoué. |
| SF-40 | Erreurs et interruptions | Gérer refus d'écriture, échec de création du dossier, interruption audio et fermeture imprévue ; afficher un message utile et ne pas effacer silencieusement un enregistrement existant. |
| SF-41 | Indépendance de la lecture | REC ne démarre ni n'arrête le moteur et n'impose pas de chargement de fichier ; la capture reflète fidèlement le signal réellement produit par l'application pendant la période enregistrée, y compris les silences. |

**Règles métier RM-23 à RM-28 :**

- **RM-23 :** REC est un interrupteur à deux états : inactif → en cours → inactif ; un appui ne lance pas plusieurs sessions simultanées.
- **RM-24 :** l'enregistrement prend le signal de mixage interne après les effets et contrôles de volume applicatifs ; le volume physique de l'appareil n'affecte pas le fichier enregistré.
- **RM-25 :** un enregistrement abouti crée un nouveau fichier local unique sans écraser les précédents.
- **RM-26 :** une erreur d'espace libre ou d'écriture met fin à l'enregistrement et indique explicitement l'échec ou le caractère partiel du résultat.
- **RM-27 :** REC et les commandes de la platine restent utilisables en multitouch ; l'enregistrement ne modifie pas la lecture.
- **RM-28 :** une interruption audio met fin à la capture et déclenche une finalisation sûre, si possible ; il n'y a pas de reprise automatique sans action de l'utilisateur.

**Scénarios Gherkin — P2 :**

```gherkin
Feature: Enregistrement du scratch sur le stockage local
  En tant que musicien
  Je veux enregistrer le son produit par ma platine
  Afin de conserver mes scratchs sur mon iPhone ou mon iPad

  Background:
    Given l'application est ouverte
    And l'option Enregistrement est disponible
    And le dossier local "Enregistrements" est accessible ou peut être créé

  Scenario: Démarrer l'enregistrement au premier appui
    Given aucun enregistrement n'est en cours
    And l'espace disponible permet la création d'un fichier
    When j'appuie sur "REC"
    Then l'enregistrement du mix audio commence immédiatement
    And le bouton indique l'état "Enregistrement"
    And un compteur de durée démarre

  Scenario: Arrêter et sauvegarder au second appui
    Given un enregistrement est en cours
    When j'appuie à nouveau sur "REC"
    Then l'enregistrement s'arrête
    And le fichier audio est finalisé
    And il est sauvegardé dans le dossier local "Enregistrements"
    And son nom et son emplacement me sont indiqués

  Scenario: Rechercher le fichier dans Fichiers
    Given un enregistrement a été sauvegardé avec succès
    When j'ouvre Fichiers dans "Sur mon iPhone" ou "Sur mon iPad"
    And j'ouvre le dossier de l'application puis "Enregistrements"
    Then je retrouve le fichier audio enregistré
    And je peux l'ouvrir avec une application compatible

  Scenario: Capturer un scratch et les coupures au crossfader
    Given un sample est chargé et audible
    And l'enregistrement est en cours
    When je scratche vers l'avant puis l'arrière
    And je ferme puis ouvre le crossfader
    And j'arrête l'enregistrement
    Then le fichier contient les mouvements audio du scratch
    And il restitue les coupures du crossfader

  Scenario: Enregistrer sans démarrer automatiquement le moteur
    Given le moteur est arrêté
    When j'appuie sur "REC"
    Then l'enregistrement commence
    And le moteur reste arrêté
    And le fichier peut contenir du silence tant qu'aucun son n'est produit

  Scenario: Conserver les effets activés dans l'enregistrement
    Given l'option Crépitement vinyle est implémentée et activée
    And un fichier audio est chargé
    When je démarre REC
    And je scratche le fichier avec le crépitement audible
    And j'arrête REC
    Then l'enregistrement contient le mix du fichier et du crépitement

  Scenario: Stockage insuffisant avant l'enregistrement
    Given l'espace libre ne permet pas de créer un enregistrement valide
    When j'appuie sur "REC"
    Then l'enregistrement ne démarre pas
    And un message m'informe que l'espace de stockage est insuffisant
    And aucun fichier vide n'est annoncé comme sauvegardé

  Scenario: Stockage épuisé pendant l'enregistrement
    Given un enregistrement est en cours
    When l'écriture échoue faute d'espace disponible
    Then la capture s'arrête proprement
    And un message indique que l'espace est insuffisant
    And l'application tente de préserver la partie déjà enregistrée
    And elle indique si un fichier partiel a pu être récupéré

  Scenario: Créer automatiquement le dossier d'enregistrement
    Given le dossier "Enregistrements" n'existe pas encore
    And l'espace de stockage est suffisant
    When je termine mon premier enregistrement
    Then l'application crée le dossier dans son espace Documents
    And le nouveau fichier y est sauvegardé

  Scenario: Conserver plusieurs prises sans écrasement
    Given un premier enregistrement a été sauvegardé
    When je réalise un deuxième enregistrement
    Then un nouveau fichier de nom unique est créé
    And le premier fichier reste inchangé

  Scenario: Gérer une interruption audio pendant REC
    Given un enregistrement est en cours
    When iOS interrompt la session audio de l'application
    Then l'enregistrement est arrêté
    And l'application tente de finaliser le fichier existant
    And aucune reprise d'enregistrement n'a lieu automatiquement

  Scenario: Gérer un échec d'écriture indépendant du stockage
    Given un enregistrement est en cours
    When une erreur d'écriture survient
    Then la capture s'arrête proprement
    And l'utilisateur reçoit un message d'échec explicite
    And aucun succès de sauvegarde n'est annoncé à tort
```

**Points ouverts [P2] :** préciser les caractéristiques WAV, la politique de conservation des fichiers partiels et le comportement si l'utilisateur force la fermeture de l'application pendant REC. L'accès au dossier via Fichiers nécessite une configuration adaptée de l'application iOS ; son existence dans le sandbox ne suffit pas à le rendre visible.

### 10.4 Gestion automatique des pointeurs par fichier audio — P2

**Objectif :** mémoriser des positions préférées pour scratcher dans une piste mono ou stéréo (une seule timeline par fichier). Cette fonction ne nécessite **aucune création, ouverture, sauvegarde ou suppression de projet**. Une fiche interne de métadonnées est créée automatiquement dès le chargement d'un fichier ; les pointeurs y sont enregistrés au fur et à mesure, sans toucher au fichier audio original.

**Interface future :** bouton « Ajouter un pointeur » et liste de boutons numérotés « Pointeur 1 », « Pointeur 2 », etc., sans nom obligatoire. Chaque bouton permet le rappel immédiat d'une position. Chaque pointeur dispose d'une action de suppression distincte. Afficher au moins dix pointeurs par page et fournir une pagination dès que nécessaire. La numérotation est un identifiant visuel ; la position mémorisée est stockée à la précision de la timeline audio (pas seulement à la seconde entière).

**Exigences fonctionnelles :**

| ID | Exigence | Résultat attendu |
|---|---|---|
| SF-42 | Fiche audio automatique | Dès le chargement d'un fichier, retrouver ou créer sa fiche interne de métadonnées sans procédure de projet. |
| SF-43 | Identification fiable | Identifier le même contenu audio avec une empreinte numérique stable des octets, indépendamment du nom ou du chemin ; éviter de confondre deux fichiers distincts portant le même nom. |
| SF-44 | Ajouter un pointeur | Mémoriser la position courante de la tête de lecture, moteur tournant ou arrêté, avec sauvegarde persistante immédiate. |
| SF-45 | Boutons de rappel | Présenter des pointeurs numérotés sans saisie de nom ; un appui rappelle exactement la position enregistrée. |
| SF-46 | Respect de l'état du disque | Rappeler un pointeur modifie uniquement la position de lecture, sans démarrer, arrêter ni changer le sens ou la vitesse du moteur ; lecture continue si le moteur tourne, scratch manuel disponible s'il est arrêté. |
| SF-47 | Suppression individuelle | Supprimer un pointeur choisi sans modifier les autres ni le fichier audio, avec sauvegarde de la suppression. |
| SF-48 | Quantité et pagination | Permettre plus de dix pointeurs par piste et présenter au moins dix entrées par page avec navigation ; seule une limite technique raisonnable peut être appliquée. |
| SF-49 | Restauration | Lorsqu'un même contenu audio est rechargé, restaurer automatiquement les pointeurs et leur ordre, y compris après redémarrage de l'application. |
| SF-50 | Robustesse des données | Signaler les erreurs de persistance et ne pas annoncer une sauvegarde qui a échoué ; garder les fichiers audio inchangés et ne pas mélanger les pointeurs entre pistes. |

**Règles métier :**

- **RM-29 :** chaque pointeur est un repère temporel associé à une seule piste audio, non une portion copiée ni une boucle.
- **RM-30 :** aucun projet utilisateur explicite n'est nécessaire ; la création de fiche et l'enregistrement des pointeurs sont automatiques.
- **RM-31 :** un rappel de pointeur change uniquement la position de lecture, quel que soit l'état du moteur ; cet état est conservé à l'identique.
- **RM-32 :** un pointeur peut être créé et rappelé avec le moteur à l'arrêt ; l'utilisateur peut scratcher manuellement sans START.
- **RM-33 :** un même contenu rechargé retrouve les mêmes pointeurs ; deux contenus différents, même nommés pareil, ont des listes distinctes.
- **RM-34 :** les métadonnées résident dans l'espace de stockage privé de l'application, séparément du fichier audio ; une base SQLite ou une autre persistance locale adaptée est acceptable.
- **RM-35 :** la suppression ne retire que le pointeur concerné. Les pointeurs restants conservent leurs positions ; la présentation pourra renuméroter leurs libellés séquentiels sans modifier leurs identifiants internes.

```gherkin
Feature: Gestion automatique des pointeurs de scratch
  En tant que DJ
  Je veux retrouver des positions de scratch mémorisées pour chaque fichier
  Afin de les rappeler instantanément sans gérer de projets

  Scenario: Créer automatiquement une fiche pour un nouveau fichier
    Given aucun fichier identique n'a encore été chargé
    When j'importe un fichier audio valide
    Then une fiche de métadonnées est créée automatiquement pour son contenu
    And aucune action « Nouveau projet » ou « Sauvegarder projet » n'est demandée
    And la liste de pointeurs est vide

  Scenario: Ajouter un pointeur avec le moteur arrêté
    Given un fichier de durée 3 minutes 12 secondes est chargé
    And le moteur est arrêté
    And la tête de lecture est à 1 minute 3 secondes
    When j'appuie sur « Ajouter un pointeur »
    Then un bouton « Pointeur 1 » apparaît
    And sa position mémorisée est de 63 secondes
    And le pointeur est sauvegardé automatiquement
    And le moteur reste arrêté

  Scenario: Ajouter plusieurs pointeurs sans les nommer
    Given « Pointeur 1 » existe à 63 secondes
    And la tête de lecture est à 95 secondes
    When j'appuie sur « Ajouter un pointeur »
    Then un bouton « Pointeur 2 » apparaît
    And aucun nom ne m'est demandé
    And les deux positions sont conservées

  Scenario: Rappeler un pointeur pendant la lecture motorisée
    Given le moteur tourne à 33⅓ tours par minute
    And « Pointeur 1 » mémorise 63 secondes
    When j'appuie sur « Pointeur 1 »
    Then la tête de lecture se positionne immédiatement à 63 secondes
    And la lecture continue depuis cette position
    And le moteur continue de tourner à sa vitesse cible

  Scenario: Rappeler un pointeur lorsque le moteur est arrêté
    Given le moteur est arrêté
    And « Pointeur 1 » mémorise 63 secondes
    When j'appuie sur « Pointeur 1 »
    Then la tête de lecture se positionne immédiatement à 63 secondes
    And le moteur reste arrêté
    And aucune lecture automatique ne commence
    When je déplace le vinyle manuellement
    Then je peux scratcher autour de cette position

  Scenario: Rappeler un pointeur sans modifier le sens motorisé
    Given le mode Reverse optionnel est actif
    And le moteur tourne en lecture inversée
    And « Pointeur 1 » mémorise 63 secondes
    When j'appuie sur « Pointeur 1 »
    Then la tête de lecture est repositionnée à 63 secondes
    And la lecture motorisée continue en sens inverse

  Scenario: Rappeler un pointeur pendant un geste de scratch
    Given je contrôle le disque avec un doigt
    And un pointeur mémorise 63 secondes
    When j'appuie sur ce pointeur avec un autre doigt
    Then la position audio est repositionnée à 63 secondes
    And le moteur conserve son état précédent
    And mon geste tactile reste prioritaire sur le moteur

  Scenario: Supprimer uniquement un pointeur
    Given trois pointeurs sont enregistrés sur le fichier
    When je supprime le deuxième pointeur
    Then ce pointeur n'est plus proposé
    And les deux autres positions restent sauvegardées
    And le fichier audio n'est pas modifié

  Scenario: Naviguer parmi plus de dix pointeurs
    Given quinze pointeurs sont enregistrés
    When j'ouvre la liste des pointeurs
    Then au moins dix pointeurs sont accessibles sur la première page
    And une commande de pagination est disponible
    When je passe à la page suivante
    Then je peux rappeler les pointeurs restants

  Scenario: Retrouver les pointeurs au prochain chargement
    Given j'ai enregistré des pointeurs dans un fichier audio
    And j'ai fermé l'application
    When je relance l'application puis recharge le même contenu audio
    Then les pointeurs précédemment sauvegardés réapparaissent
    And leurs positions sont identiques
    And aucun projet n'a besoin d'être ouvert

  Scenario: Identifier un fichier renommé par son contenu
    Given un fichier possède des pointeurs sauvegardés
    When je recharge ce même contenu sous un nom différent
    Then la liste de pointeurs du fichier est retrouvée

  Scenario: Séparer deux fichiers ayant le même nom
    Given deux fichiers audio différents portent le même nom
    And seul le premier possède un pointeur
    When je charge le deuxième fichier
    Then le pointeur du premier fichier n'apparaît pas

  Scenario: Ne pas annoncer à tort une sauvegarde impossible
    Given un fichier est chargé et une erreur de stockage survient
    When j'ajoute un pointeur
    Then l'application signale que le pointeur n'a pas pu être sauvegardé
    And elle ne prétend pas qu'il sera disponible au prochain lancement
    And la lecture du disque reste utilisable
```

**Point d'ergonomie à valider ultérieurement :** distinction visuelle entre rappel du pointeur et suppression ; gestuelle lors du rappel avec un doigt déjà sur le vinyle. Les boutons ne modifient jamais le moteur. Un très court lissage audio peut éviter les clics de repositionnement, sans décaler la position cible.

### 10.5 Enregistrement microphone et banque de sons — P2

**Objectif :** permettre de créer un nouveau sample en enregistrant la voix, un instrument ou un bruit avec le microphone intégré de l’iPhone/iPad (ou une entrée audio sélectionnée par iOS/iPadOS), puis de charger cet enregistrement directement sur la platine virtuelle pour le scratcher. Cette fonction est **distincte** de l’option 10.3 « Enregistrement audio local », qui capture la sortie/mix de la platine.

**Décision de bibliothèque :** la banque est une bibliothèque physique locale, et non un catalogue de signets ou de chemins distants. Les sons importés depuis Fichiers y sont copiés ; les enregistrements micro y sont créés directement. Les deux catégories apparaissent dans la même bibliothèque. Toute suppression doit être confirmée et ne peut pas effacer le fichier source externe. Les pointeurs sont attachés à un identifiant interne stable de la copie, indépendamment de son nom physique, et restent dans des métadonnées internes distinctes. Un menu contextuel accessible par appui long permet de renommer localement les fichiers importés et les prises micro.

**Parcours nominal :** ouvrir la « Banque de sons » → toucher « Enregistrer au micro » → autoriser le micro si nécessaire → toucher REC pour démarrer → toucher STOP pour terminer → l’enregistrement est sauvegardé automatiquement en local et apparaît dans la banque → toucher « Charger sur la platine » → le son est prêt à être scratché, moteur arrêté, à la position 0.

**Exigences SF-51 à SF-63 :**

| ID | Exigence | Description |
|---|---|---|
| SF-51 | Accès à la banque | Proposer une interface « Banque de sons » accessible depuis la platine, affichant les fichiers importés déjà copiés et les enregistrements micro, avec une commande « Enregistrer au micro ». |
| SF-52 | Autorisation microphone | Demander l'autorisation iOS/iPadOS au premier usage du micro ; si elle est refusée ou désactivée, informer l'utilisateur et permettre d'ouvrir les Réglages, sans empêcher le chargement de sons existants. |
| SF-53 | Commande d'enregistrement | Un bouton REC démarre effectivement la capture du microphone ; un second appui (ou STOP) termine et finalise l'enregistrement. Afficher clairement l'état et la durée écoulée. Aucune capture ne débute à la seule ouverture de l'écran. |
| SF-54 | Sauvegarde locale automatique | Écrire un fichier audio non protégé et exploitable par la platine (WAV PCM proposé par défaut) dans le répertoire de documents de l'application, sous-dossier « Banque de sons », visible dans Fichiers si le partage des documents est activé ; attribuer un nom automatique unique au format `REC_AAAAMMJJ_HHMMSS.wav` (heure locale de l’appareil), avec suffixe numérique en cas de collision, sans saisie obligatoire. |
| SF-55 | Consultation de la banque | Afficher les sons importés et les prises micro avec au minimum nom, durée, date et origine (« Import » ou « Micro ») ; permettre de les charger sur la platine depuis la copie locale. La banque persiste après fermeture de l’application. |
| SF-56 | Chargement et scratch | Le chargement d'un enregistrement micro fonctionne comme l'import d'un fichier compatible : il remplace le son courant suivant les règles de confirmation existantes, remet la position à zéro et garde le moteur arrêté ; les scratchs avant/arrière, pitch et crossfader fonctionnent normalement. |
| SF-57 | Erreurs de capture et stockage | Refuser ou arrêter proprement une capture si le micro est indisponible, si le stockage local est insuffisant ou si l'écriture échoue ; informer l'utilisateur et ne pas ajouter de fichier invalide à la banque. Conserver une prise partielle uniquement si elle est valide et clairement signalée. |
| SF-58 | Indépendance du REC mix | Distinguer clairement « Enregistrer au micro » et « Enregistrer le mix de la platine » ; la première fonction capte l'entrée micro, pas la sortie de scratch. L'une n'active pas automatiquement l'autre. |
| SF-59 | Gestion des prises | Permettre la suppression d'une prise depuis la banque après confirmation ; si la prise est chargée sur la platine, éviter la suppression silencieuse d'un fichier en cours d'usage et préserver l'intégrité de la liste. |
| SF-60 | Nom des fichiers importés | Conserver le nom de fichier d'origine lors de la copie locale ; en cas de collision de nom dans le dossier de l'application, attribuer un suffixe numérique unique, sans écraser l'existant. |
| SF-61 | Nommage des prises microphone | À la finalisation d'une prise, créer un fichier `REC_AAAAMMJJ_HHMMSS.wav` à partir de la date et de l'heure locales ; en cas de collision, ajouter un suffixe numérique avant l'extension. |
| SF-62 | Renommage depuis la banque | Un appui long sur un son, qu'il provienne de Fichiers ou du micro, ouvre un menu contextuel contenant « Charger sur la platine », « Renommer » et « Supprimer ». « Renommer » permet de changer le nom physique de la copie dans le dossier de l'application, sans passer par Fichiers iOS. Refuser les noms invalides et les collisions non résolues, sans perdre le fichier. |
| SF-63 | Identité stable et pointeurs | Attribuer un identifiant interne stable à chaque élément de la banque. Le renommage doit préserver cet identifiant, les pointeurs associés et la possibilité de charger le son. Une erreur de renommage laisse le nom et les métadonnées intacts. |


**Règles métier :**

- **RM-36 :** une prise micro produit un nouveau fichier audio personnel qui peut être chargé et scratché comme n'importe quel autre fichier compatible.
- **RM-37 :** la permission micro est préalable à toute capture ; l'application ne doit jamais enregistrer sans action explicite.
- **RM-38 :** la banque est locale et persistante, sans transfert vers un service en ligne ; l'enregistrement n'exige pas de connexion Internet.
- **RM-39 :** le fichier ne devient visible comme prise finalisée que si sa fermeture et sa validation ont réussi ; les échecs sont signalés.
- **RM-40 :** charger une prise depuis la banque respecte les règles existantes de changement de source, sans démarrer automatiquement le moteur.
- **RM-41 :** l'enregistrement au micro et l'enregistrement de la sortie audio (10.3) sont deux actions différentes, avec des destinations et intitulés clairement identifiables.
- **RM-42 :** l'identité de la prise peut ensuite servir à la gestion automatique des pointeurs (option 10.4), comme pour tout autre fichier chargé.
- **RM-43 :** le nom physique du fichier d'une prise micro suit par défaut `REC_AAAAMMJJ_HHMMSS.wav` ; le nom d'un fichier importé est conservé sauf collision, résolue par un suffixe numérique.
- **RM-44 :** le menu « Renommer » appartient à l'application Scratch, dans sa banque locale, et ne dépend pas de l'application Fichiers d'iOS.
- **RM-45 :** un renommage ne change pas l'identité interne du son et ne doit supprimer, déplacer vers une autre piste, ni invalider ses pointeurs de scratch.
- **RM-46 :** une erreur de renommage (nom interdit, conflit, problème d'écriture) n'affecte ni le fichier existant ni son index de bibliothèque.


```gherkin
Feature: Enregistrement microphone et banque de sons
  En tant que DJ
  Je veux enregistrer un son avec le micro de mon iPhone ou iPad
  Afin de le retrouver dans ma banque et de le scratcher

  Scenario: Afficher ensemble les imports et les prises micro
    Given un son a été importé depuis Fichiers
    And une prise a été enregistrée au microphone
    When j'ouvre la « Banque de sons »
    Then les deux sons apparaissent dans la même liste
    And leur origine « Import » ou « Micro » est identifiable

  Scenario: La source externe est supprimée après import
    Given un son a été copié dans la banque depuis Drive
    And son fichier source sur Drive a été supprimé
    When je recharge le son depuis la banque
    Then la copie locale est utilisée
    And le son est lisible sans rechercher le chemin externe

  Scenario: Suppression d'un son importé depuis la banque
    Given un son importé est présent dans la banque locale
    When je confirme la suppression de ce son
    Then sa copie locale est supprimée selon la politique de sécurité de l'application
    And son original externe n'est pas modifié

  Scenario: Ouvrir la banque de sons vide
    Given aucune prise microphone n'a été enregistrée
    When j'ouvre la « Banque de sons »
    Then la liste est vide
    And une commande « Enregistrer au micro » est disponible

  Scenario: Autoriser le microphone au premier enregistrement
    Given l'autorisation microphone n'a pas encore été demandée
    When je choisis « Enregistrer au micro »
    Then iOS ou iPadOS me demande l'accès au microphone
    When j'autorise l'accès
    Then je peux démarrer un enregistrement
    And l'application ne commence pas à enregistrer sans appui sur REC

  Scenario: Refuser l'autorisation microphone
    Given l'accès microphone est refusé
    When je tente d'enregistrer au micro
    Then aucune capture ne démarre
    And un message explique comment activer l'accès dans les Réglages
    And je peux toujours consulter les sons déjà enregistrés

  Scenario: Démarrer et arrêter une prise microphone
    Given l'autorisation microphone est accordée
    And le microphone est disponible
    When j'appuie sur REC dans l'écran d'enregistrement micro
    Then la capture microphone démarre
    And un indicateur d'enregistrement et une durée écoulée s'affichent
    When j'appuie de nouveau sur REC
    Then la capture s'arrête
    And la prise est finalisée dans la banque de sons

  Scenario: Enregistrer une prise avec un nom automatique
    Given l'autorisation microphone est accordée
    When j'enregistre une prise et termine la capture
    Then un fichier WAV valide est sauvegardé dans « Banque de sons »
    And un nom unique est attribué automatiquement
    And aucune saisie de nom n'est obligatoire

  Scenario: Nommer une prise micro à partir de la date et de l'heure
    Given l'heure locale de l'appareil est le 12 novembre 2026 à 10:28:03
    And une capture microphone vient de se terminer avec succès
    When la prise est sauvegardée dans la banque
    Then son nom de fichier est "REC_20261112_102803.wav"
    And ce fichier est visible dans la bibliothèque

  Scenario: Éviter une collision entre deux prises micro
    Given "REC_20261112_102803.wav" existe déjà dans la banque
    When une autre prise est finalisée à la même seconde
    Then un nom distinct comportant un suffixe numérique est attribué
    And la première prise n'est pas écrasée

  Scenario: Conserver le nom d'un fichier importé
    Given "voix_funk.wav" a été sélectionné dans Fichiers
    And aucun fichier de ce nom n'existe dans le dossier de la banque
    When l'import et la copie locale réussissent
    Then le nom de la copie locale est "voix_funk.wav"
    And le fichier d'origine reste inchangé

  Scenario: Importer deux fichiers portant le même nom
    Given "voix_funk.wav" existe déjà dans la banque
    When j'importe un autre fichier nommé "voix_funk.wav"
    Then un nom de copie locale unique avec suffixe numérique est attribué
    And aucun fichier préexistant n'est écrasé

  Scenario Outline: Renommer un son depuis la banque
    Given la banque contient un son d'origine "<origine>"
    When je fais un appui long sur ce son
    Then le menu contextuel propose "Charger sur la platine", "Renommer" et "Supprimer"
    When je sélectionne "Renommer"
    And je saisis "mon_scratch.wav" comme nouveau nom disponible
    And je confirme
    Then le fichier local est renommé "mon_scratch.wav"
    And le son reste disponible dans la banque
    Examples:
      | origine |
      | Import  |
      | Micro   |

  Scenario: Préserver les pointeurs lors d'un renommage
    Given un son dispose de pointeurs enregistrés à 63 et 125 secondes
    And son identité interne est stable
    When je renomme ce son dans la banque
    And je le recharge sur la platine
    Then les pointeurs à 63 et 125 secondes sont toujours présents
    And ils restent associés au même son

  Scenario: Annuler un renommage
    Given un son est présent dans la banque
    When j'ouvre "Renommer"
    And j'annule l'opération
    Then le fichier garde son nom d'origine
    And ses pointeurs restent inchangés

  Scenario: Échec de renommage
    Given un son est présent dans la banque
    When je tente un renommage vers un nom invalide ou indisponible
    Then un message d'erreur compréhensible est affiché
    And le fichier existant reste accessible sous son ancien nom
    And ses métadonnées et pointeurs restent intacts

  Scenario: Charger une prise sur la platine
    Given ma banque contient une prise microphone valide
    And le moteur est arrêté
    When je choisis « Charger sur la platine » pour cette prise
    Then la prise devient le fichier audio du disque
    And la position de lecture est à zéro
    And le moteur reste arrêté
    When je déplace manuellement le disque vers l'avant et l'arrière
    Then le son enregistré est scratché dans les deux sens

  Scenario: Remplacer une piste en cours de lecture
    Given un fichier audio est en cours de lecture
    And la banque contient une prise microphone
    When je choisis de charger cette prise
    Then une confirmation de remplacement est demandée
    When je confirme le remplacement
    Then la prise est chargée sur le disque
    And le moteur est arrêté

  Scenario: Retrouver les prises après relancement
    Given une prise microphone a été sauvegardée
    When je ferme puis relance l'application
    And j'ouvre la banque de sons
    Then la prise est encore présente
    And je peux la charger sans nouvel enregistrement

  Scenario: Empêcher un enregistrement si l'espace est insuffisant
    Given l'espace libre disponible ne permet pas d'enregistrer une nouvelle prise
    When j'appuie sur REC
    Then la capture ne démarre pas
    And un message signale le manque d'espace disponible
    And aucune prise invalide n'est créée

  Scenario: Gérer un disque plein pendant l'enregistrement
    Given une capture microphone est en cours
    When le stockage devient insuffisant pour poursuivre l'écriture
    Then la capture s'arrête proprement
    And l'utilisateur est informé de l'erreur
    And aucune prise corrompue n'est présentée comme finalisée

  Scenario: Distinguer l'enregistrement micro de celui du mix
    Given un fichier audio est chargé sur la platine
    When je démarre « Enregistrer au micro »
    Then seule la source microphone est sélectionnée pour cette prise
    And l'option « Enregistrer le mix » n'est pas activée automatiquement

  Scenario: Supprimer une prise de la banque
    Given la banque contient plusieurs prises enregistrées
    When je demande la suppression d'une prise non chargée
    And je confirme la suppression
    Then cette prise disparaît de la banque
    And les autres prises restent intactes

  Scenario: Conserver la prise lorsque la suppression est annulée
    Given une prise existe dans la banque
    When je demande sa suppression
    And j'annule la confirmation
    Then la prise reste disponible et inchangée

  Scenario: Retrouver les pointeurs d'une prise microphone
    Given la gestion des pointeurs est disponible
    And une prise microphone possède des pointeurs sauvegardés
    When je recharge cette prise depuis la banque
    Then ses pointeurs sont restaurés automatiquement
    And aucun projet n'a besoin d'être ouvert
```

**Point ouvert P2 :** définir à terme une politique anti-doublons fondée sur le contenu (même contenu sélectionné plusieurs fois) et de suppression des métadonnées associées à une copie. Pour l’instant, la règle décidée reste une copie locale, sans référencement distant.

**Point ouvert P2 :** préciser les cas où l'utilisateur tente de capter le microphone pendant que le moteur de scratch produit du son (monitoring, écoute au casque, prévention du larsen). Par défaut, aucune écoute micro amplifiée ne sera activée sans demande explicite.

### 10.6 Critères de recette futurs (non bloquants pour la V1)

- [ ] Reverse motorisé : transition sans saut, scratch avant/arrière toujours possible, reprise en sens inverse après relâchement.
- [ ] Crépitement vinyle : activation autonome, volume indépendant, persistance pendant scratch/STOP/reverse, extinction sans clic.
- [ ] Enregistrement : premier appui REC démarre, second appui finalise un WAV dans le dossier local de l’application ; les scratchs sont capturés et les erreurs de stockage sont correctement signalées.
- [ ] Pointeurs : ajout/suppression/rappel, pagination, restauration automatique par empreinte du fichier et conservation intégrale de l’état moteur.
- [ ] Banque de sons locale : imports copiés et prises micro réunis, ouverture hors ligne, REC/STOP, erreur stockage et suppression protégée sans toucher à l’original externe.
- [ ] Nommage et renommage : nom original des imports, `REC_AAAAMMJJ_HHMMSS.wav` pour le micro, suffixes anti-collision, menu Renommer depuis la banque, conservation des pointeurs.
