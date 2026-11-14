# ScratchApp — Spécifications fonctionnelles et scénarios Gherkin

- **Version :** 2.0 — refonte explicite de la v1.9 (« Platine Scratch 33 »)
- **Date :** 14 novembre 2026
- **Nom de l'application :** ScratchApp
- **Plateformes cibles :** iPhone (iOS 17+), iPad (iPadOS 17+), Mac (macOS 14 Sonoma+)
- **Objectif :** reproduire une **double platine vinyle 33⅓ tours avec table de mixage** pour scratcher des fichiers audio personnels, au doigt (iPhone, iPad) ou à la souris, au trackpad et au clavier (Mac).
- **Statut :** base de référence pour le développement V1. Les décisions prises à la revue sont signalées **[Décision v2.0]**. La revue complète (incohérences, scénarios ajoutés, évolutions) est dans [`REVUE_v1.9_vers_v2.0.md`](REVUE_v1.9_vers_v2.0.md).

## 0. Conventions

### 0.1 Identifiants

- Les identifiants SF, RM et PO de la v1.9 sont conservés.
- **Seule exception :** les trois règles de copie locale ajoutées en v1.8 portaient les numéros RM-43 à RM-45, déjà attribués en v1.9 aux règles de nommage (section 10.5). Elles deviennent **RM-47, RM-48 et RM-49**.
- Nouveaux identifiants v2.0 : **SF-64 à SF-83**, **RM-50 à RM-61**, **PO-12 à PO-16**, **E-01 à E-12** (évolutions).

### 0.2 Vocabulaire

| Terme | Définition |
|---|---|
| Platine A / Platine B | Les deux platines virtuelles, identiques et indépendantes. |
| Plateau | Partie motorisée qui tourne à la vitesse du moteur. |
| Disque (vinyle) | Ce que l'utilisateur touche. Il repose sur le plateau par l'intermédiaire de la feutrine. |
| Feutrine (slipmat) | Interface glissante entre plateau et disque : on peut retenir le disque pendant que le plateau continue de tourner. |
| Tête de lecture | Position courante dans le son, exprimée en secondes. |
| Amorce | Silence virtuel de 2 s placé avant le début du son (position −2 s à 0). |
| Sillon fermé | Comportement en fin de son : la tête reste à la fin, en silence, pendant que le disque continue de tourner. |
| Fader de voie | Volume propre à une platine, de 0 à 100 %. |
| Crossfader | Curseur horizontal qui répartit le son entre A (gauche) et B (droite). |
| Courbe | Forme de la réponse du crossfader, de « douce » à « coupure franche ». |
| Hamster | Inversion du sens du crossfader (A à droite, B à gauche). |
| Repère | Marque visuelle (autocollant) sur l'étiquette du disque, alignée sur le point CUE. |

### 0.3 Équivalences entre plateformes

| Concept iPhone/iPad | Équivalent Mac |
|---|---|
| Sélecteur **Fichiers** d'Apple | Panneau d'ouverture macOS (Finder), menu Fichier › Importer… (⌘O) |
| Glisser-déposer depuis Fichiers (iPad) | Glisser-déposer depuis le Finder |
| Doigt posé sur le disque | Clic maintenu (bouton principal) sur le disque |
| Rotation au doigt | Clic-glisser circulaire, ou défilement à deux doigts sur le trackpad |
| Multitouch (disque + crossfader) | Souris ou trackpad pour le disque, **clavier** pour le crossfader et les coupures |
| Interruption de session audio (appel, Siri, alarme) | Changement de configuration audio, mise en veille, périphérique retiré |
| Passage en arrière-plan | Fenêtre inactive : la lecture continue (comportement Mac standard) |
| Fichiers › Sur mon iPhone/iPad › ScratchApp | Conteneur de l'app, ouvert par le menu « Afficher la bibliothèque dans le Finder » |
| Route audio iOS (AVAudioSession) | Périphérique de sortie par défaut du système (Réglages Système › Son) |

## 1. Vision et périmètre

L'utilisateur charge un son sur chacune des deux platines : un son importé, un son de sa bibliothèque locale ou le son de démonstration. Il fait tourner les plateaux motorisés, retient un disque, le pousse et le ramène en arrière. Le moteur sonore suit la position et la vitesse de chaque disque en temps réel. Avec le crossfader et les faders de voie, il coupe et mélange les deux platines, comme sur une vraie installation de scratch : deux platines et une table de mixage.

Le scratch n'est **pas** un effet préenregistré : il est calculé à partir du son chargé.

### Inclus en V1

- **Deux platines virtuelles (A et B)** et une **table de mixage** : faders de voie, crossfader A↔B à courbe réglable, inversion hamster, VU-mètres. [E-01, E-02]
- Une sortie audio stéréo.
- Import local, iCloud Drive ou disque Mac via le sélecteur de documents du système, et par glisser-déposer (iPad, Mac). Chaque import est copié dans le stockage de l'app.
- **Bibliothèque locale minimale** : liste des sons copiés, chargement sur A ou B, suppression. [E-07]
- **Son de démonstration** intégré, libre de droits. [E-08]
- Formats WAV, AIFF, MP3, M4A (AAC/ALAC) non protégés, sous réserve du décodage système. Mono, stéréo ou multicanal (réduit en stéréo).
- Lecture 33⅓ RPM par défaut, option 45 RPM, par platine.
- Commandes START/STOP, PITCH (−8 % à +8 %), SET CUE/CUE, par platine.
- **Feutrine** : le plateau continue de tourner sous le disque retenu. Le rattrapage au relâchement est quasi immédiat. Durées de démarrage et de freinage réglables. [E-03]
- Résistance du vinyle réglable, par platine.
- **Repère visuel** sur le disque, **forme d'onde** défilante et positionnement direct dans le son (needle drop). [E-04]
- **Amorce silencieuse** avant le son et **sillon fermé** en fin de son. [E-05]
- Manipulation multitouch sur iPhone/iPad : deux disques et le crossfader en même temps.
- **Commandes Mac** : souris, trackpad, clavier (coupures, crossfader, transport), menus et raccourcis. [E-09]
- Lecture avant et arrière, à vitesse et hauteur variables, avec une interpolation de qualité. [E-06]
- Affichage du titre, de la durée, de la position et de la sortie audio.
- Sorties audio reconnues par le système, y compris USB.
- Gestion des erreurs, des interruptions, des changements de sortie et du passage en arrière-plan.
- Préférences conservées entre les lancements.
- Accessibilité de base : VoiceOver et navigation au clavier sur Mac. [E-12]

### Options reportées après la V1 (P2)

- **Reverse motorisé** (10.1).
- **Crépitement vinyle** (10.2).
- **Enregistrement du mix audio** (10.3).
- **Gestion automatique des pointeurs** (10.4).
- **Enregistrement microphone et banque de sons complète** (10.5) : prises micro, renommage, menu contextuel. Elle étend la bibliothèque minimale V1.
- **Nouvelles options v2.0** (10.7) : contrôleur MIDI, plages de pitch ±16 %/±50 %, retour haptique, effets de freinage (« power down »).

### Hors périmètre

Synchronisation BPM, stems en temps réel, effets complexes, export et partage avancés, plugin Logic Pro, vinyle timecode (DVS), services de streaming, plus de deux platines.

## 2. Parcours nominal

1. L'utilisateur ouvre l'application.
2. Les deux platines et la table de mixage s'affichent, sans lecture automatique. Sur iPhone en portrait, une seule platine est visible ; on passe de A à B avec un sélecteur.
3. Il touche **Importer** sur la platine A, ou fait glisser un fichier dessus (iPad, Mac).
4. Le sélecteur natif s'ouvre : Fichiers sur iPhone/iPad, panneau d'ouverture sur Mac.
5. Il choisit un audio compatible. L'application en crée une copie durable dans son stockage local, l'ajoute à la bibliothèque, puis l'ouvre sur la platine A.
6. Le titre et la durée sont affichés. La tête est au début du son (0 s), le repère est aligné sur ce point et le moteur est à l'arrêt.
7. Il charge un second son sur la platine B (import, bibliothèque ou démo).
8. Il touche **START** sur A. Le plateau accélère jusqu'à sa vitesse cible et la lecture suit la rotation.
9. Il pose un doigt sur le disque A (ou clique dessus sur Mac). Le disque s'immobilise quand le doigt reste fixe, mais le plateau continue de tourner dessous (feutrine).
10. Il pousse et tire le disque. Le son avance et recule à la vitesse de son geste.
11. Avec un autre doigt (ou le clavier sur Mac), il manipule le crossfader pour rythmer les coupures entre A et B.
12. Il relâche le disque. Si le moteur est actif, le disque rattrape le plateau presque instantanément (60 ms par défaut) et la lecture reprend depuis la position atteinte.
13. Il touche **STOP**. La rotation ralentit puis s'arrête, sans perdre sa position.

## 3. Interface utilisateur

### 3.1 Par platine (A et B)

- Disque animé, surface tactile interactive, avec un **repère** sur l'étiquette.
- Bouton **Importer** (et zone de dépôt de fichier).
- Bouton **START / STOP**.
- Sélecteur **33⅓ / 45 RPM**, réglé sur 33⅓ au premier lancement.
- Curseur **PITCH** de −8 % à +8 % par pas de 0,1 %, valeur initiale 0 %, avec affichage numérique et remise à zéro (double-toucher ou bouton « 0 »).
- Curseur **RÉSISTANCE DU VINYLE** (léger ↔ lourd), réglable pendant le scratch, 50 % par défaut.
- Boutons **SET CUE** (mémoriser) et **CUE** (rappeler). **[Décision v2.0]** Les deux boutons sont distincts ; cela clôt l'« interaction équivalente à préciser » de la v1.9.
- **Forme d'onde** : bande zoomée qui défile sous la tête de lecture, et aperçu complet du son. Toucher l'aperçu positionne la tête (needle drop).
- Titre, durée, position de lecture (mm:ss.d).

### 3.2 Table de mixage

- **Fader de voie A** et **fader de voie B** (0–100 %, 100 % par défaut).
- **Crossfader** horizontal : A à gauche, B à droite, position initiale au centre.
- Réglage de **courbe** du crossfader (douce ↔ coupure franche), « coupure franche » par défaut.
- Interrupteur **Hamster** (inversion du crossfader), désactivé par défaut.
- **VU-mètre** par voie et indicateur de saturation de la sortie.
- Indication de la sortie audio active (ex. « Haut-parleur », « Casque », « MPC Sample (USB) »).

### 3.3 Accès secondaires

- **Bibliothèque** : liste des sons copiés et du son de démonstration. Actions : charger sur A, charger sur B, supprimer.
- **Réglages** : durées de démarrage et de freinage, temps de rattrapage de la feutrine, aide sur les raccourcis clavier (Mac).

### 3.4 Disposition par appareil

| Appareil | Disposition |
|---|---|
| iPhone portrait | Une platine plein écran (sélecteur A/B) + crossfader et fader de voie en bas, accessibles au pouce. |
| iPhone paysage | Deux platines réduites à gauche et à droite, table de mixage au centre. |
| iPad portrait | Deux platines empilées ou côte à côte selon la largeur, table de mixage entre les deux. |
| iPad paysage et Mac | Platine A à gauche, table de mixage au centre, platine B à droite. Le Mac accepte toute taille de fenêtre au-delà d'un minimum de 960 × 600 points. |

Le design graphique détaillé est défini dans la spécification UX (`docs/bmad/front-end-spec.md`).

### 3.5 Commandes clavier Mac (configuration par défaut)

| Action | Platine A | Platine B | Global |
|---|---|---|---|
| START / STOP | `Q` | `P` | — |
| SET CUE / CUE | `A` / `S` | `L` / `K` | — |
| Coupure momentanée (maintenir = ouvrir la voie) | `F` | `J` | — |
| Pitch −/+ 0,1 % | `Z` / `X` | `,` / `.` | — |
| Crossfader : déplacer par pas de 5 % | — | — | `←` / `→` |
| Crossfader : butée A / centre / butée B | — | — | `⇧←` / `⇧↓` / `⇧→` |
| Importer sur A / sur B | — | — | `⌘O` / `⇧⌘O` |
| Bibliothèque | — | — | `⌘L` |

Une **coupure momentanée** (« transformer ») ouvre la voie tant que la touche est maintenue et la ferme au relâchement. C'est le moyen de rythmer un scratch à la souris : le pointeur tient le disque, la main gauche coupe le son au clavier.

### 3.6 Interfaces futures (P2 uniquement)

Interrupteur REVERSE, module Crépitement vinyle ON/OFF avec niveau 0–100 %, bouton REC (mix), banque de sons complète (micro, renommage) et panneau de pointeurs. Ces contrôles ne sont pas requis pour la recette V1.

## 4. Exigences fonctionnelles V1

Sauf mention contraire, les exigences SF-03 à SF-24 s'appliquent **à chaque platine** (A et B) de façon indépendante (voir SF-64).

| ID | Exigence | Résultat attendu |
|---|---|---|
| SF-01 | Ouverture | Afficher les platines et la table de mixage sans lecture automatique. Sur une platine vide, proposer l'import et le son de démonstration. |
| SF-02 | Import audio et copie | Ouvrir le sélecteur du système (Fichiers ou Finder) et accepter les fichiers WAV, AIFF, MP3 et M4A décodables et non protégés. Copier le fichier dans le dossier local de l'application, sans modifier la source. Le chargement ultérieur repose sur cette copie, jamais sur un signet ou un chemin externe. En cas d'échec de copie ou d'espace insuffisant, signaler l'erreur et ne pas ajouter de fichier incomplet. Le fichier est chargé sur la platine depuis laquelle l'import a été lancé. |
| SF-03 | Initialisation | Après chargement : titre et durée affichés, tête au début du son (0 s), repère aligné, moteur arrêté. |
| SF-04 | START | Accélérer progressivement jusqu'à la vitesse cible pendant la durée de démarrage (0,7 s par défaut). L'audio suit la vitesse réelle. |
| SF-05 | STOP | Décélérer jusqu'à zéro pendant la durée de freinage (1,0 s par défaut) et conserver la position audio. Le scratch manuel reste disponible moteur arrêté. |
| SF-06 | Prise en main | Le geste sur le disque prend la priorité sur le moteur. Un doigt immobile retient le disque. Moteur actif, le plateau continue de tourner sous le disque (feutrine, SF-68). |
| SF-07 | Scratch avant | Une rotation manuelle vers l'avant avance dans l'audio. |
| SF-08 | Scratch arrière | Une rotation manuelle inverse lit l'audio à l'envers. |
| SF-09 | Vitesse du geste | La vitesse et la hauteur de lecture suivent le mouvement du disque, avec une interpolation audio adaptée (SF-77). |
| SF-10 | Relâchement | Moteur actif : le disque rattrape la vitesse du plateau en un temps de rattrapage court (60 ms par défaut) depuis la position atteinte. Moteur arrêté : le disque ralentit naturellement jusqu'à l'arrêt en 150 ms au plus, et aucune lecture motorisée ne démarre. |
| SF-11 | Pitch | Modifier la vitesse nominale de −8 % à +8 % par pas de 0,1 %, en modifiant aussi la hauteur. Remise à 0 % en un geste. |
| SF-12 | Crossfader | Le crossfader modifie uniquement le gain de sortie de chaque voie, sans altérer la position de lecture (voir SF-65 à SF-67). |
| SF-13 | CUE | **SET CUE** mémorise la position de la tête. **CUE** y ramène la tête sans changer l'état du moteur. Sans CUE défini, CUE ramène au début du son (0 s). Le CUE est propre à chaque platine et réinitialisé au chargement d'un autre son. |
| SF-14 | Limites du fichier | La tête reste dans l'intervalle [−2 s ; durée]. Elle se bloque à la borne de l'amorce en reculant, et à la fin du son en avançant (sillon fermé, RM-55). Aucune lecture hors limites ni clic anormal. |
| SF-15 | Remplacement | Si la platine cible est **active** (moteur en marche, disque en mouvement ou tenu), demander confirmation avant de remplacer son son. Si elle est à l'arrêt, remplacer directement. Après remplacement, la platine revient à l'état initial (SF-03). Le son précédent reste disponible dans la bibliothèque. L'autre platine n'est jamais affectée. |
| SF-16 | Sortie audio | Utiliser la route audio active du système : route iOS/iPadOS, ou périphérique de sortie par défaut sur macOS, y compris une interface USB compatible. Suivre les changements de route sans plantage. |
| SF-17 | Préférences | Conserver, par platine, la vitesse (RPM), le pitch et la résistance. Conserver aussi la position du crossfader, sa courbe, le hamster, les faders de voie et les durées moteur. Ne jamais relancer automatiquement l'audio. Les sons chargés ne sont pas rechargés automatiquement en V1 (voir PO-12). |
| SF-18 | Interruptions | Lors d'une interruption système, passer chaque moteur à l'état STOP, conserver les positions et exiger une reprise manuelle (RM-56). |
| SF-19 | Multitouch | Sur iPhone/iPad, permettre au moins trois contacts simultanés et indépendants : disque A, disque B et crossfader (ou un fader de voie), sans perte de contrôle. |
| SF-20 | Absence de réseau | Fonctionner entièrement hors ligne. La bibliothèque est locale et l'app n'exige aucune connexion. |
| SF-21 | Résistance réglable | Proposer sur chaque platine un curseur « Résistance du vinyle » de 0 à 100 %, de léger à lourd, ajustable en temps réel. |
| SF-22 | Effet de la résistance | À geste identique, une résistance élevée atténue les accélérations et variations de vitesse excessives ; une résistance faible donne une réponse plus directe. Le moteur sonore suit le mouvement simulé du disque, pas directement celui du doigt. |
| SF-23 | Continuité du réglage | Modifier la résistance ne fait pas sauter la position de lecture et ne provoque ni clic audio ni inversion inattendue. Le contrôle du disque reste prioritaire sur le moteur. |
| SF-24 | Préférence de résistance | Mémoriser la dernière valeur de résistance de chaque platine pour les lancements suivants, sans lecture automatique. |
| SF-64 | Deux platines | Fournir deux platines A et B identiques et indépendantes : son, moteur, RPM, pitch, CUE, résistance et repère propres à chacune. Toutes les exigences SF-03 à SF-24 s'appliquent à chaque platine. |
| SF-65 | Table de mixage | Fournir un fader de voie par platine (0–100 %, 100 % par défaut), un crossfader A↔B et un VU-mètre par voie. Le gain d'une voie est le produit de son fader de voie et du gain que lui donne le crossfader. La somme des voies ne doit pas produire d'écrêtage numérique : une marge et un limiteur doux sont appliqués en sortie. |
| SF-66 | Courbe du crossfader | Proposer un réglage continu, de « douce » (puissance constante, −3 dB au centre) à « coupure franche ». En coupure franche, une voie passe du silence au plein niveau sur 3 % au plus de la course, depuis la butée opposée (« cut-in »). Valeur par défaut : coupure franche. |
| SF-67 | Hamster | Un interrupteur inverse le sens du crossfader. La bascule est sans clic : transition de gain lissée sur 5 ms au plus. |
| SF-68 | Feutrine et couple moteur | Moteur actif, retenir le disque n'arrête pas le plateau. Au relâchement, le disque rejoint la vitesse du plateau en un temps de rattrapage réglable de 0 à 300 ms (60 ms par défaut), sans discontinuité audible. Les durées de démarrage (0,7 s) et de freinage (1,0 s) sont réglables de 0,1 à 5 s. |
| SF-69 | Repère visuel | Afficher sur l'étiquette du disque un repère (autocollant) dont l'angle correspond à la position du CUE (ou à 0 s sans CUE). Le repère tourne avec le disque. |
| SF-70 | Forme d'onde | Afficher pour chaque platine une forme d'onde zoomée centrée sur la tête de lecture (environ ±1,8 s, soit un tour de disque de chaque côté) et un aperçu complet du son, avec la position de la tête et du CUE. L'affichage suit le scratch sans retard visible (rafraîchissement ≥ 60 i/s). |
| SF-71 | Needle drop | Toucher l'aperçu complet place la tête à la position correspondante, sans changer l'état du moteur. Ce geste est ignoré tant que le disque de cette platine est tenu. Le repositionnement est lissé (≤ 5 ms) pour éviter un clic. |
| SF-72 | Amorce silencieuse | Chaque son est précédé d'une amorce silencieuse de 2 s (positions −2 s à 0). On peut ainsi reculer avant l'attaque du son et l'attaquer en poussant le disque. La position initiale après chargement reste 0 s. |
| SF-73 | Glisser-déposer | Déposer un fichier audio sur une platine (depuis Fichiers sur iPad, depuis le Finder sur Mac) l'importe comme SF-02, puis le charge sur cette platine selon SF-15. Un fichier non compatible est refusé avec un message. |
| SF-74 | Bibliothèque minimale | Afficher la liste des sons copiés (nom, durée, date d'import, origine), les charger sur A ou sur B, et les supprimer après confirmation. Le son de démonstration apparaît en tête et ne peut pas être supprimé. La bibliothèque persiste entre les lancements. Le renommage et les prises micro sont en P2 (10.5). |
| SF-75 | Dédoublonnage | Importer un contenu identique (même empreinte SHA-256) à une entrée existante n'ajoute pas de seconde copie : l'entrée existante est réutilisée et chargée. |
| SF-76 | Son de démonstration | Fournir un son de démonstration libre de droits, embarqué ou généré par l'app, pour essayer le scratch sans import. Il ne se charge jamais automatiquement (RM-01). |
| SF-77 | Qualité audio du scratch | Interpolation au moins cubique. Pas de discontinuité aux inversions de sens. Repliement atténué aux vitesses élevées (au-delà de 2×). Vitesse de lecture bornée à ±16× la vitesse nominale. Pas de souffle ni de grésillement « en escalier » dû à une mise à jour trop lente de la vitesse (paramètres lissés à la fréquence audio). |
| SF-78 | Latence | Objectifs : tampon audio de 256 trames à 48 kHz (≈5,3 ms) au plus lorsque le matériel le permet ; latence geste→son de 20 ms au plus sur iPhone/iPad récents et Mac. Le suivi tactile exploite tous les événements disponibles (touches regroupées et prédites). La latence mesurée est consignée dans la recette. |
| SF-79 | Commandes Mac | Clic-glisser sur le disque = doigt posé. Défilement à deux doigts sur le trackpad au-dessus du disque = rotation du disque, relâchée 80 ms après le dernier événement. Clavier selon 3.5. Menus Fichier, Platine et Table avec leurs raccourcis. Le scratch à la souris et le crossfader au clavier fonctionnent simultanément. |
| SF-80 | Formats, canaux, fréquences | Le mono est dupliqué sur les deux canaux, la stéréo conservée, le multicanal réduit en stéréo. Toute fréquence d'échantillonnage est convertie vers celle de la sortie sans changer la hauteur nominale. Durée maximale acceptée : 10 minutes par son en V1 ; au-delà, l'import est refusé avec un message explicite. Durée minimale : 50 ms. |
| SF-81 | Cycle de vie | iPhone/iPad : en arrière-plan, chaque moteur passe à STOP, la sortie est coupée et les positions sont conservées. L'audio en arrière-plan n'est pas pris en charge en V1. Mac : la lecture continue quand la fenêtre est inactive ; fermer la dernière fenêtre quitte l'application. |
| SF-82 | Sortie indisponible | Si aucune sortie audio n'est disponible ou si le moteur audio ne peut démarrer, afficher un état « Sortie audio indisponible ». L'interface reste utilisable et l'app réessaie automatiquement dès qu'une sortie apparaît. Jamais de plantage. |
| SF-83 | Accessibilité | Chaque commande porte un libellé VoiceOver. Pitch, résistance, faders et crossfader sont ajustables par les actions d'accessibilité et, sur Mac, au clavier. Contraste conforme WCAG AA pour les libellés. |

## 5. Règles métier V1

- **RM-01 :** sans son chargé, une platine n'émet aucun son.
- **RM-02 :** la vitesse nominale initiale de chaque platine est 33⅓ RPM.
- **RM-03 :** le toucher manuel est prioritaire sur l'entraînement moteur.
- **RM-04 :** le déplacement angulaire du disque détermine le déplacement temporel dans le son (voir RM-50).
- **RM-05 :** une rotation inverse produit une lecture inverse réelle, et non un bruit de scratch préenregistré.
- **RM-06 :** le crossfader et les faders de voie ne changent jamais la position de lecture.
- **RM-07 :** le relâchement n'entraîne une reprise motorisée que si le moteur est actif.
- **RM-08 :** les variations de vitesse et de gain évitent autant que possible les discontinuités audibles.
- **RM-09 :** le lecteur ne lit jamais d'échantillon hors des bornes du fichier audio. L'amorce est un silence virtuel, pas une lecture hors bornes.
- **RM-10 :** aucune interruption système ne provoque une reprise sonore automatique.
- **RM-11 :** la résistance change la réponse dynamique du disque au geste. Elle ne change ni la hauteur ni la vitesse nominale du moteur en l'absence de manipulation.
- **RM-12 :** une résistance élevée ne doit pas rendre le scratch impossible : l'utilisateur doit toujours pouvoir déplacer le disque dans les deux sens et l'immobiliser en gardant son doigt fixe.
- **RM-13 :** les variations de résistance ne désynchronisent jamais la position visuelle du disque, la position audio et le geste (hors sillon fermé, RM-55).
- **RM-47 (ex-RM-43 v1.8) :** tout fichier sélectionné dans le sélecteur du système ou déposé sur une platine est copié dans le stockage propre à l'application. Sa source reste inchangée et n'est pas nécessaire aux rechargements suivants.
- **RM-48 (ex-RM-44 v1.8) :** aucune entrée de bibliothèque ne peut référencer une copie locale incomplète ou absente. Une erreur de stockage est signalée sans altérer le son en cours.
- **RM-49 (ex-RM-45 v1.8) :** supprimer une entrée de la bibliothèque supprime sa copie dans l'application, jamais le fichier original (Drive, Fichiers, Finder).
- **RM-50 :** le son est considéré comme **gravé à 33⅓ tours** : un tour complet du disque correspond à 1,8 s de son. La vitesse de lecture vaut `ω / (2π × 33⅓ / 60)`, où ω est la vitesse angulaire du disque en rad/s. À 45 RPM, le son est donc lu 1,35× plus vite et plus aigu, comme un vrai 33 tours joué en 45. **[Décision v2.0]**
- **RM-51 :** les deux platines sont indépendantes. Aucune commande d'une platine ne modifie l'état de l'autre ; seule la table de mixage combine leurs sorties.
- **RM-52 :** gain de sortie d'une voie = fader de voie × gain du crossfader pour cette voie. Les deux facteurs sont lissés à la fréquence audio (≤ 5 ms) ; le crossfader en coupure franche garde un temps de montée de 1 ms au plus pour rester percutant.
- **RM-53 :** feutrine : moteur actif, le plateau tourne toujours à la vitesse moteur, que le disque soit tenu ou non. Un toucher n'arrête jamais le moteur et ne change pas son état START/STOP.
- **RM-54 :** la résistance n'agit que sur la réponse au geste. Elle ne modifie ni les durées de démarrage et de freinage ni le temps de rattrapage au relâchement.
- **RM-55 :** sillon fermé : en fin de son, la tête reste sur la fin (silence) tant que le disque avance ; le disque et le repère continuent de tourner. Un mouvement arrière fait immédiatement revenir dans le son, sans « dérouler » les tours accumulés. La borne de l'amorce (−2 s) se comporte de la même façon en sens inverse.
- **RM-56 :** interruption système ou passage en arrière-plan (iPhone/iPad) : chaque moteur passe immédiatement à l'état STOP, sans rampe puisque la sortie est coupée. L'état arrêté est affiché et les positions sont conservées.
- **RM-57 :** une platine ne porte qu'un son à la fois. Charger un son sur une platine ne modifie jamais l'autre. Le même son peut être chargé sur les deux platines en même temps.
- **RM-58 :** chaque entrée de bibliothèque possède un identifiant interne stable (UUID) et une empreinte de contenu (SHA-256). L'identifiant ne change jamais, même après un renommage (P2). L'empreinte sert au dédoublonnage (SF-75) et à l'association des pointeurs (P2, 10.4). Cela concilie SF-43 et SF-63.
- **RM-59 :** sur Mac, un clic maintenu équivaut à un doigt posé. La souris n'offrant qu'un pointeur, la simultanéité passe par le clavier : coupures momentanées et crossfader (3.5).
- **RM-60 :** un geste ne saisit un disque que s'il **commence** sur ce disque ; un contact qui glisse depuis l'extérieur ne le saisit pas. Un second doigt sur un disque déjà tenu est ignoré. Un toucher annulé par le système (geste système, notification, rotation de l'écran) équivaut à un relâchement.
- **RM-61 :** dans une zone centrale (rayon inférieur à 12 % du rayon du disque), l'angle du doigt n'est pas fiable. Un doigt posé dans cette zone retient le disque sans le faire tourner. Si le doigt en sort, le suivi angulaire reprend depuis l'angle courant, sans saut.

### 5.1 Précision de conception — Modèle physique de la platine

Le réglage de résistance porte sur **la sensation de lourdeur du disque**, pas sur un simple ralentissement graphique. Il module la réactivité du disque virtuel aux accélérations rapides du doigt, et donc la réponse sonore. Le contact fixe doit toujours pouvoir arrêter le disque et la latence perçue doit rester faible.

Modèle de référence, à calibrer sur appareil :

1. **Plateau** : vitesse angulaire `ωp` qui tend vers la cible `ωt = 2π × RPM/60 × (1 + pitch)` quand le moteur est actif, vers 0 sinon. La pente vaut `ωt / durée de démarrage` à l'accélération et `ωt / durée de freinage` à la décélération.
2. **Disque libre** (non tenu) : couplé au plateau par la feutrine. Sa vitesse `ωd` rejoint `ωp` avec une constante de temps égale au temps de rattrapage (60 ms par défaut). Moteur arrêté, un disque lancé ralentit par friction jusqu'à 0 en 150 ms au plus.
3. **Disque tenu** : l'angle du disque `θd` suit l'angle du doigt `θf` à travers un filtre du second ordre à amortissement critique. Sa constante de temps varie de 2 ms (résistance 0 %) à 35 ms (résistance 100 %). Un doigt fixe entraîne la convergence de `θd` vers `θf` et une vitesse nulle (RM-12).
4. **Tête de lecture** : `p += ωd / (2π) × 1,8 s × dt`, bornée à [−2 s ; durée] (RM-55), avec `dt` la période d'échantillonnage. L'intégration se fait **à la fréquence audio**, dans le fil de rendu. Les positions du doigt (60 à 120 Hz) sont interpolées pour éviter les marches de vitesse.
5. **Géométrie du geste** : angle du doigt mesuré par `atan2` autour du centre du disque, avec dépliement des tours (pas de saut à ±π) et zone morte centrale (RM-61). Le gain de déplacement tactile reste 1:1 en V1 (un tour de doigt = un tour de disque).

Un éventuel **gain de déplacement tactile** réglable reste un paramètre distinct, non retenu en V1.

### 5.2 Précision de conception — Courbe du crossfader

Soit `x ∈ [0 ; 1]` la position du crossfader (0 = butée A, 1 = butée B ; inversée si hamster) et `c ∈ [0 ; 1]` la courbe (0 = douce, 1 = coupure franche) :

- Douce (`c = 0`) : `gA = cos(x·π/2)`, `gB = sin(x·π/2)` (puissance constante).
- Coupure franche (`c = 1`) : `gB = min(1, x / w)` et `gA = min(1, (1 − x) / w)`, avec une largeur de cut-in `w = 0,03`.
- Valeurs intermédiaires : `w = lerp(1, 0,03, c)` et une interpolation de forme entre les deux familles, de sorte que `c` varie de façon monotone et perceptible.

### 5.3 Précision de conception — Stockage

| Contenu | Emplacement (dans le bac à sable de l'app) |
|---|---|
| Copies des sons importés | `Documents/Banque de sons/` (visible dans Fichiers sur iPhone/iPad ; menu « Afficher dans le Finder » sur Mac) |
| Index de bibliothèque (UUID, empreinte, nom, durée, dates, origine) | `Application Support/ScratchApp/library.json` (écriture atomique) |
| Préférences | `UserDefaults` |
| Enregistrements du mix (P2) | `Documents/Enregistrements/` |

Une copie est écrite d'abord dans un fichier temporaire, vérifiée (décodable, taille), puis déplacée atomiquement à sa place finale. L'index n'est mis à jour qu'ensuite (RM-48).

## 6. Scénarios Gherkin — classés par priorité

**P0 — Critique :** parcours minimal pour charger un son sur deux platines, faire tourner un disque, scratcher et couper le son au crossfader, sur iPhone, iPad et Mac.

**P1 — Important :** compléments de la V1 (robustesse, périphériques, pitch/CUE, sensation tactile, repère, bibliothèque, accessibilité).

**P2 — Option future :** fonctionnalités exclues de la recette V1, spécifiées en fin de document.

> Convention : lorsqu'un scénario ne nomme pas la platine, il s'applique à la platine A et doit être vrai à l'identique pour la platine B.

### 6.1 [P0] Lancement et import

```gherkin
Feature: Lancement et importation d'un fichier audio
  En tant qu'utilisateur
  Je veux charger un fichier audio depuis Fichiers ou le Finder
  Afin de le scratcher sur une platine virtuelle

  Scenario: Premier lancement sans fichier
    Given l'application n'a aucun fichier chargé
    When je lance l'application
    Then les platines A et B et la table de mixage sont affichées
    And les disques sont immobiles
    And aucun son n'est joué
    And chaque platine propose "Importer" et "Charger la démo"

  Scenario: Importer un fichier WAV
    Given la platine A est affichée
    When j'appuie sur "Importer" de la platine A
    Then le sélecteur de documents du système s'ouvre
    When je sélectionne un fichier WAV valide
    Then une copie complète du fichier est créée dans le dossier de l'application
    And le fichier est ajouté à la bibliothèque
    And le fichier est chargé sur la platine A depuis cette copie
    And son titre et sa durée sont affichés
    And la position de lecture est à zéro
    And le moteur de la platine A est arrêté
    And la platine B n'est pas modifiée

  Scenario Outline: Importer un format audio compatible
    Given le sélecteur de documents est ouvert
    When je sélectionne un fichier "<format>" valide
    Then le fichier est chargé
    And la platine est prête à être utilisée

    Examples:
      | format     |
      | WAV        |
      | AIFF       |
      | MP3        |
      | M4A (AAC)  |
      | M4A (ALAC) |

  Scenario: Importer depuis le Finder sur Mac
    Given l'application est ouverte sur Mac
    When je choisis le menu "Fichier › Importer sur la platine A…" ou j'appuie sur ⌘O
    Then le panneau d'ouverture de macOS s'ouvre, filtré sur les formats audio compatibles
    When je sélectionne un fichier MP3 valide
    Then une copie est créée dans le conteneur de l'application
    And le fichier est chargé sur la platine A

  Scenario: Recharger un son déjà importé sans accéder à Drive
    Given un fichier audio a été importé et copié dans le dossier de l'application
    And sa source d'origine est devenue inaccessible
    When je choisis ce son dans la bibliothèque et "Charger sur A"
    Then le son est chargé depuis sa copie locale
    And aucune connexion à Drive n'est nécessaire

  Scenario: Échec de copie faute d'espace
    Given le stockage libre est insuffisant pour copier le fichier sélectionné
    When je tente de l'importer
    Then un message « Espace de stockage insuffisant » est affiché
    And aucune copie incomplète n'est conservée comme son utilisable
    And aucune entrée n'est ajoutée à la bibliothèque
    And le fichier précédemment chargé reste disponible et son état est conservé

  Scenario: Un import ne modifie pas le fichier source
    Given un fichier valide existe dans iCloud Drive
    When je l'importe dans l'application
    Then une copie distincte est stockée dans le dossier de l'application
    And le fichier dans iCloud Drive reste inchangé

  Scenario: Annuler l'importation
    Given le sélecteur de documents est ouvert
    When j'annule la sélection
    Then je reviens à la platine
    And le fichier précédemment chargé est conservé
    And son état de lecture est inchangé

  Scenario: Importer un fichier incompatible
    Given le sélecteur de documents est ouvert
    When je sélectionne un fichier non décodable
    Then un message d'erreur indiquant que le format n'est pas pris en charge est affiché
    And aucun fichier invalide n'est chargé ni ajouté à la bibliothèque
    And l'application reste utilisable

  Scenario: Importer un fichier protégé
    Given le sélecteur de documents est ouvert
    When je sélectionne un fichier M4A protégé par DRM
    Then un message indique que les fichiers protégés ne sont pas pris en charge
    And aucune copie n'est conservée

  Scenario: Importer un fichier corrompu ou vide
    Given le sélecteur de documents est ouvert
    When je sélectionne un fichier WAV tronqué ou de taille nulle
    Then un message d'erreur est affiché
    And aucune entrée n'est ajoutée à la bibliothèque

  Scenario: Importer un fichier trop long
    Given le sélecteur de documents est ouvert
    When je sélectionne un fichier valide de 25 minutes
    Then un message indique que la durée maximale est de 10 minutes
    And aucune copie n'est conservée

  Scenario: Importer un contenu déjà présent dans la bibliothèque
    Given "boucle.wav" a déjà été importé
    When j'importe un fichier "copie de boucle.wav" au contenu identique
    Then aucune seconde copie n'est créée
    And l'entrée existante de la bibliothèque est chargée sur la platine

  Scenario: Charger le son de démonstration
    Given aucune platine n'a de son chargé
    When j'appuie sur "Charger la démo" de la platine A
    Then le son de démonstration est chargé sur la platine A
    And aucun son n'est joué tant que je n'ai pas appuyé sur START ou touché le disque
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
    And le disque accélère progressivement pendant la durée de démarrage
    And il atteint 33⅓ tours par minute
    And l'audio suit la rotation du disque

  Scenario: Arrêter la platine
    Given le moteur tourne à 33⅓ RPM
    When j'appuie sur "STOP"
    Then le disque ralentit progressivement pendant la durée de freinage
    And le son ralentit avec le disque
    And le disque finit par s'immobiliser
    And la position audio est conservée

  Scenario: Sélectionner 45 tours
    Given le moteur est arrêté
    When je sélectionne "45 RPM"
    And j'appuie sur "START"
    Then le disque accélère jusqu'à 45 RPM
    And le son est lu 1,35 fois plus vite et plus aigu qu'à 33⅓ RPM

  Scenario: Modifier la vitesse pendant la lecture
    Given le moteur tourne à 33⅓ RPM
    When je sélectionne "45 RPM"
    Then le moteur rejoint progressivement 45 RPM
    And la lecture suit la nouvelle vitesse
    And la position audio reste continue

  Scenario: Démarrer sans fichier
    Given aucun fichier audio n'est chargé sur la platine
    When j'appuie sur "START"
    Then le plateau tourne
    And aucun son n'est joué
    And l'application propose d'importer un fichier ou de charger la démo

  Scenario: Appuyer sur STOP pendant que je retiens le disque
    Given le moteur tourne
    And je retiens le disque immobile avec un doigt
    When j'appuie sur "STOP" avec un autre doigt
    Then le plateau ralentit jusqu'à l'arrêt sous le disque
    And le disque reste sous mon contrôle
    When je relâche le disque
    Then il reste immobile et aucune lecture motorisée ne démarre

  Scenario: Appuyer sur START pendant le freinage
    Given j'ai appuyé sur "STOP" et le disque ralentit
    When j'appuie sur "START"
    Then le disque réaccélère depuis sa vitesse courante jusqu'à la vitesse cible
    And aucun saut de position ni clic ne se produit

  Scenario: Régler les durées de démarrage et de freinage
    Given la durée de freinage est réglée à 3 secondes dans les réglages
    When j'appuie sur "STOP" alors que le moteur tourne
    Then le disque met environ 3 secondes à s'immobiliser
    And le son ralentit progressivement jusqu'au silence
```

### 6.3 [P0] Scratch tactile

```gherkin
Feature: Manipulation tactile du vinyle
  En tant que DJ
  Je veux manipuler le disque avec mon doigt
  Afin de produire des scratchs naturels

  Rule: Moteur actif

    Background:
      Given un fichier audio est chargé
      And le moteur tourne à 33⅓ RPM
      And la voie de la platine est audible

    Scenario: Poser le doigt sur le disque
      When je pose un doigt sur la surface du vinyle
      And je maintiens mon doigt immobile
      Then le disque cesse de tourner
      And le plateau continue de tourner sous le disque
      And la vitesse de lecture est nulle et aucun son n'est produit
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

    Scenario: Enchaîner des inversions rapides (baby scratch)
      Given je maintiens le disque avec mon doigt
      When j'alterne avant et arrière huit fois par seconde sur un quart de tour
      Then chaque inversion est audible
      And aucun clic ni craquement numérique ne se produit
      And la position audio revient à son point de départ à ±10 ms près

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
      Then le disque rattrape la vitesse du plateau en 60 ms environ
      And la lecture reprend depuis la position actuelle
      And la vitesse rejoint 33⅓ RPM
      And aucune discontinuité audible ne se produit

    Scenario: Lancer le son depuis le repère (« release »)
      Given je retiens le disque avec le repère aligné sur l'attaque du son
      When je relâche le disque d'un coup
      Then l'attaque du son est jouée presque immédiatement à la vitesse nominale

    Scenario: Saisir le disque en rotation
      Given le disque tourne librement à 33⅓ RPM
      When je pose le doigt sur le disque en mouvement
      Then le disque suit mon doigt depuis la position courante
      And aucun saut de position ne se produit

  Rule: Moteur arrêté

    Background:
      Given un fichier audio est chargé
      And le moteur est complètement arrêté après STOP
      And la voie de la platine est audible

    Scenario: Scratcher avec le moteur arrêté
      When je pousse le disque manuellement vers l'avant
      Then le son est lu vers l'avant à la vitesse de mon geste
      When je tire le disque manuellement vers l'arrière
      Then le son est lu à l'envers à la vitesse de mon geste
      And le moteur reste arrêté

    Scenario: Relâcher le disque moteur arrêté
      Given je manipule le disque manuellement
      When je retire mon doigt
      Then le disque s'arrête en 150 ms au plus
      And aucune lecture automatique ne démarre

  Rule: Gestes particuliers

    Background:
      Given un fichier audio est chargé
      And le moteur tourne à 33⅓ RPM

    Scenario: Geste commencé hors du disque
      When je pose le doigt à côté du disque
      And je le fais glisser sur le disque
      Then le disque n'est pas saisi
      And la lecture motorisée continue normalement

    Scenario: Deuxième doigt sur le même disque
      Given je retiens le disque avec un premier doigt
      When je pose un deuxième doigt sur le même disque et le déplace
      Then le deuxième doigt est ignoré
      And le disque reste contrôlé par le premier doigt

    Scenario: Toucher annulé par le système
      Given je retiens le disque avec un doigt
      When le système annule le toucher (geste système, notification, rotation de l'écran)
      Then le disque est considéré comme relâché
      And il rattrape la vitesse du plateau
      And il ne reste pas bloqué dans l'état « tenu »

    Scenario: Doigt posé au centre du disque
      When je pose le doigt au centre de l'étiquette, dans la zone centrale
      Then le disque est retenu sans tourner de façon erratique
      When je fais glisser le doigt vers le bord puis tourne le disque
      Then le suivi angulaire reprend sans saut de position
```

### 6.4 [P0] Crossfader et table de mixage

```gherkin
Feature: Contrôle du crossfader
  En tant que DJ
  Je veux couper et rétablir rapidement le son d'une platine
  Afin d'exécuter des scratchs rythmiques

  Background:
    Given un fichier audio est chargé sur la platine A
    And le moteur de la platine A est actif
    And la courbe du crossfader est réglée sur "coupure franche"
    And le hamster est désactivé

  Scenario: Fermer complètement la voie A au crossfader
    Given le crossfader est en butée A
    When je le déplace en butée B
    Then la voie A devient silencieuse
    And la lecture de la platine A continue à sa position normale

  Scenario: Ouvrir la voie A au crossfader
    Given le crossfader est en butée B
    When je le déplace en butée A
    Then le son de la platine A redevient audible
    And la lecture n'est pas repositionnée

  Scenario: Ouvrir la voie avec un déplacement minimal (cut-in)
    Given le crossfader est en butée B
    When je le déplace de 3 % de sa course vers A
    Then la voie A est audible à plein niveau

  Scenario: Scratch avec coupure rythmique
    Given mon premier doigt contrôle le disque A
    And mon deuxième doigt contrôle le crossfader
    When j'effectue un scratch avant-arrière
    And j'ouvre et ferme plusieurs fois le crossfader
    Then le son n'est audible que pendant les ouvertures
    And les deux commandes fonctionnent simultanément
    And le disque reste contrôlé par mon premier doigt

  Scenario: Crossfader en position intermédiaire avec courbe douce
    Given la courbe du crossfader est réglée sur "douce"
    And un son est chargé et audible sur chaque platine
    When je place le crossfader au centre
    Then chaque voie est atténuée d'environ 3 dB
    And la position de lecture des deux platines est inchangée

  Scenario: Fader de voie
    Given le crossfader est en butée A
    When je règle le fader de voie A à 50 %
    Then le niveau de la voie A diminue
    And la position de lecture est inchangée
    And la platine B n'est pas affectée
```

### 6.5 [P1] Cycle de vie et sortie audio

```gherkin
Feature: Cycle de vie et sortie audio

  Scenario: Charger un deuxième fichier sur une platine active
    Given un fichier est chargé sur la platine A et son moteur tourne
    When j'importe un nouveau fichier sur la platine A
    Then une confirmation de remplacement apparaît
    When je confirme
    Then l'ancien fichier est déchargé de la platine A
    And il reste disponible dans la bibliothèque
    And le nouveau fichier est chargé
    And le moteur est arrêté
    And la position audio est à zéro
    And la platine B n'est pas affectée

  Scenario: Charger un deuxième fichier sur une platine à l'arrêt
    Given un fichier est chargé sur la platine A
    And le moteur de la platine A est arrêté et le disque immobile
    When j'importe un nouveau fichier sur la platine A
    Then le nouveau fichier est chargé sans demande de confirmation

  Scenario: Refuser le remplacement
    Given un fichier est en cours de lecture sur la platine A
    When je sélectionne un autre fichier pour la platine A
    And je refuse le remplacement
    Then le fichier initial reste chargé
    And son état de lecture est conservé
    And le nouveau fichier reste disponible dans la bibliothèque

  Scenario: Recevoir une interruption système (iPhone/iPad)
    Given le moteur de la platine A tourne
    And je retiens le disque B
    When une interruption audio système survient
    Then les deux moteurs passent à l'état STOP
    And les positions sont conservées
    When l'interruption se termine
    Then aucun son ne reprend automatiquement
    And la reprise nécessite un appui sur START

  Scenario: Passer en arrière-plan (iPhone/iPad)
    Given le moteur de la platine A tourne
    When je quitte l'application pour l'écran d'accueil
    Then les moteurs passent à l'état STOP
    And la sortie audio est coupée
    When je reviens dans l'application
    Then les sons chargés et leurs positions sont conservés
    And aucune lecture ne reprend automatiquement

  Scenario: Fenêtre inactive sur Mac
    Given le moteur de la platine A tourne sur Mac
    When je donne le focus à une autre application
    Then la lecture continue

  Scenario: Brancher une interface audio USB
    Given une interface audio USB compatible est connectée
    And elle est sélectionnée comme sortie par le système
    When je lance la lecture
    Then le son est envoyé à cette interface
    And le nom de la sortie est affiché
    And le scratch reste opérationnel

  Scenario: Perdre le périphérique audio
    Given la lecture utilise une interface USB
    When l'interface est déconnectée
    Then l'application ne plante pas
    And elle suit la nouvelle route audio du système
    And les moteurs passent à l'état STOP
    And la reprise nécessite une action utilisateur

  Scenario: Débrancher le casque (iPhone/iPad)
    Given la lecture utilise un casque filaire ou Bluetooth
    When le casque est déconnecté
    Then les moteurs passent à l'état STOP
    And aucun son ne sort brusquement du haut-parleur

  Scenario: Changer de périphérique de sortie sur Mac
    Given la lecture utilise la sortie intégrée du Mac à 44,1 kHz
    When je choisis dans les Réglages Système une interface USB à 48 kHz
    Then le son est envoyé à la nouvelle interface
    And la hauteur et la vitesse nominale sont inchangées
    And la position de lecture est conservée

  Scenario: Aucune sortie audio disponible
    Given aucun périphérique de sortie n'est disponible
    When je lance l'application
    Then l'état « Sortie audio indisponible » est affiché
    And l'interface reste utilisable
    When un périphérique de sortie devient disponible
    Then l'application l'utilise sans redémarrage

  Scenario: Restaurer les préférences
    Given j'ai sélectionné 45 RPM sur la platine A
    And j'ai réglé le pitch de la platine A à +3 %
    And j'ai placé le crossfader en butée B avec la courbe "douce"
    When je ferme puis relance l'application
    Then la vitesse sélectionnée sur la platine A est 45 RPM
    And le pitch de la platine A est à +3 %
    And le crossfader est en butée B avec la courbe "douce"
    And aucune lecture automatique ne démarre
```

### 6.6 [P1] Pitch et CUE

```gherkin
Feature: Réglage du pitch et des points CUE
  En tant que DJ
  Je veux régler la vitesse et retrouver une position
  Afin de préparer mes scratchs

  Scenario Outline: Modifier le pitch
    Given le moteur tourne à <rpm> RPM
    When je règle le pitch sur <pitch> %
    Then la vitesse cible est <vitesse> RPM
    And la hauteur sonore suit la variation de vitesse

    Examples:
      | rpm   | pitch | vitesse |
      | 33⅓   | -8    | 30.67   |
      | 33⅓   | 0     | 33.33   |
      | 33⅓   | 8     | 36.00   |
      | 45    | -8    | 41.40   |
      | 45    | 0     | 45.00   |
      | 45    | 8     | 48.60   |

  Scenario: Remettre le pitch à zéro
    Given le pitch est réglé à +5,3 %
    When je touche deux fois le curseur de pitch
    Then le pitch revient à 0 %
    And la vitesse cible revient progressivement à la vitesse nominale

  Scenario: Mémoriser un point CUE
    Given un fichier audio est chargé
    And la position de lecture est à 12 secondes
    When j'appuie sur "SET CUE"
    Then la position de 12 secondes est mémorisée
    And le repère du disque est aligné sur cette position

  Scenario: Revenir au point CUE
    Given un point CUE existe à 12 secondes
    And la lecture est à 30 secondes
    When j'appuie sur "CUE"
    Then la lecture revient à 12 secondes
    And l'état du moteur est conservé

  Scenario: Rappeler CUE sans point enregistré
    Given aucun point CUE n'est défini
    When j'appuie sur "CUE"
    Then la lecture revient au début du son (0 s)

  Scenario: Définir un CUE pendant que je retiens le disque
    Given je retiens le disque à la position 8,25 secondes
    When j'appuie sur "SET CUE" avec un autre doigt
    Then la position 8,25 secondes est mémorisée
    And je garde le contrôle du disque

  Scenario: Rappeler le CUE pendant que je retiens le disque
    Given un point CUE existe à 12 secondes
    And je retiens le disque à 20 secondes
    When j'appuie sur "CUE" avec un autre doigt
    Then la position passe à 12 secondes sans clic
    And le disque reste sous mon doigt et suit mes mouvements depuis 12 secondes

  Scenario: Le CUE est propre à chaque son
    Given un point CUE existe à 12 secondes sur la platine A
    When je charge un autre son sur la platine A
    Then aucun point CUE n'est défini sur la platine A
    And le point CUE de la platine B est inchangé
```

### 6.7 [P1] Résistance et inertie tactile réglables

```gherkin
Feature: Réglage de la résistance du vinyle
  En tant qu'utilisateur
  Je veux régler la lourdeur du disque depuis la platine
  Afin de retrouver une sensation de scratch proche d'un vrai vinyle

  Background:
    Given un fichier audio valide est chargé
    And la voie de la platine est audible
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

  Scenario: La résistance ne ralentit pas le rattrapage
    Given la résistance est réglée à 100 %
    And je retiens le disque immobile
    When je relâche le disque
    Then le disque rattrape la vitesse du plateau dans le même temps qu'avec une résistance de 0 %

  Scenario: Restaurer le réglage mémorisé
    Given j'ai réglé la résistance de la platine A à 75 %
    When je quitte puis relance l'application
    Then la résistance affichée sur la platine A est 75 %
    And aucune lecture ne démarre automatiquement
```

### 6.8 [P0] Double platine

```gherkin
Feature: Deux platines indépendantes
  En tant que DJ scratch
  Je veux deux platines comme sur une installation réelle
  Afin de scratcher un son pendant que l'autre platine joue un rythme

  Background:
    Given un son de rythmique est chargé sur la platine B
    And un son de voix est chargé sur la platine A

  Scenario: Les platines sont indépendantes
    When j'appuie sur "START" de la platine B
    Then seul le moteur de la platine B démarre
    And la platine A reste arrêtée
    When je règle le pitch de la platine A à +4 %
    Then la vitesse de la platine B est inchangée

  Scenario: Scratcher A pendant que B joue
    Given le moteur de la platine B tourne
    And le crossfader est au centre avec la courbe "coupure franche"
    When je scratche le disque A
    Then j'entends le scratch de A mélangé au rythme de B
    And le rythme de B n'est pas perturbé

  Scenario: Charger le même son sur les deux platines
    Given le son de voix est dans la bibliothèque
    When je le charge aussi sur la platine B
    Then les deux platines portent le même son
    And chacune a sa propre position, son propre moteur et son propre CUE

  Scenario: Scratcher les deux disques en même temps sur iPad
    Given les deux platines sont visibles sur iPad
    When je manipule le disque A d'une main et le disque B de l'autre
    Then chaque disque suit le doigt qui le tient
    And les deux sons sont lus selon leurs gestes respectifs

  Scenario: Trois contacts simultanés
    Given les deux platines sont visibles sur iPad
    When je tiens le disque A, je tiens le disque B et je déplace le crossfader
    Then les trois commandes répondent simultanément

  Scenario: Passer d'une platine à l'autre sur iPhone en portrait
    Given l'iPhone est en portrait et la platine A est affichée
    And le moteur de la platine A tourne
    When je sélectionne la platine B
    Then la platine B est affichée
    And la platine A continue de tourner et de jouer
    And le crossfader reste accessible

  Scenario: Pas de saturation à la somme des deux voies
    Given deux sons normalisés à 0 dBFS jouent ensemble à plein niveau
    When le crossfader est au centre avec la courbe "coupure franche"
    Then la sortie ne présente pas d'écrêtage numérique
    And l'indicateur de saturation reste éteint ou signale l'action du limiteur
```

### 6.9 [P0] Feutrine, couple moteur et relâchement

```gherkin
Feature: Feutrine et couple moteur
  En tant que DJ
  Je veux que le plateau continue de tourner sous le disque retenu
  Afin de lancer un son instantanément en le relâchant

  Background:
    Given un fichier audio est chargé
    And le moteur tourne à 33⅓ RPM

  Scenario: Le plateau tourne sous le disque retenu
    When je retiens le disque immobile pendant 2 secondes
    Then l'indicateur du plateau continue de tourner
    And l'état du moteur reste START

  Scenario: Rattrapage réglable
    Given le temps de rattrapage est réglé à 0 ms
    When je relâche le disque retenu
    Then le son repart à la vitesse nominale sans délai perceptible
    And aucun clic numérique ne se produit

  Scenario: Rattrapage plus lent
    Given le temps de rattrapage est réglé à 300 ms
    When je relâche le disque retenu
    Then le son monte progressivement en vitesse pendant environ 300 ms

  Scenario: Démarrage court
    Given la durée de démarrage est réglée à 0,1 seconde
    And le moteur est arrêté
    When j'appuie sur "START"
    Then le disque atteint 33⅓ RPM en 0,1 seconde environ
```

### 6.10 [P1] Courbe du crossfader et hamster

```gherkin
Feature: Réglage de la courbe du crossfader et inversion hamster
  En tant que DJ scratch
  Je veux régler la courbe et le sens du crossfader
  Afin d'adapter la coupure à ma technique

  Background:
    Given un son est chargé et audible sur chaque platine

  Scenario Outline: Gain des voies selon la courbe
    Given la courbe est réglée sur "<courbe>"
    When je place le crossfader à <position> % de la course vers B
    Then le gain de la voie A vaut <gainA> à 0,05 près
    And le gain de la voie B vaut <gainB> à 0,05 près

    Examples:
      | courbe          | position | gainA | gainB |
      | coupure franche | 0        | 1.00  | 0.00  |
      | coupure franche | 3        | 1.00  | 1.00  |
      | coupure franche | 50       | 1.00  | 1.00  |
      | coupure franche | 100      | 0.00  | 1.00  |
      | douce           | 0        | 1.00  | 0.00  |
      | douce           | 50       | 0.71  | 0.71  |
      | douce           | 100      | 0.00  | 1.00  |

  Scenario: Activer le hamster
    Given le crossfader est en butée gauche
    And le hamster est désactivé
    When j'active le hamster
    Then la butée gauche correspond désormais à la voie B
    And la bascule ne produit pas de clic

  Scenario: Conserver les réglages de crossfader
    Given j'ai activé le hamster et réglé la courbe sur "douce"
    When je relance l'application
    Then le hamster est actif et la courbe est "douce"
```

### 6.11 [P1] Repère visuel, forme d'onde et needle drop

```gherkin
Feature: Repérage visuel du son
  En tant que DJ scratch
  Je veux voir où se trouve l'attaque du son sur le disque
  Afin de retrouver mes repères sans chercher à l'oreille

  Background:
    Given un fichier audio est chargé sur la platine A

  Scenario: Le repère suit le disque
    Given un point CUE est défini à 4 secondes
    When le disque tourne
    Then le repère tourne avec le disque
    And il passe sous la position de lecture quand la tête est à 4 secondes

  Scenario: La forme d'onde suit le scratch
    When je scratche le disque vers l'avant puis vers l'arrière
    Then la forme d'onde zoomée défile dans le sens du geste
    And la position affichée correspond à la position audio

  Scenario: Positionner la tête sur l'aperçu (needle drop)
    Given le moteur tourne
    And je ne touche pas le disque
    When je touche l'aperçu complet aux trois quarts de sa largeur
    Then la tête se place aux trois quarts du son
    And la lecture continue depuis cette position sans clic
    And l'état du moteur est conservé

  Scenario: Needle drop ignoré pendant que je retiens le disque
    Given je retiens le disque
    When je touche l'aperçu complet
    Then la position de la tête n'est pas modifiée
```

### 6.12 [P1] Bornes, amorce et sillon fermé

```gherkin
Feature: Bornes du son
  En tant que DJ
  Je veux un comportement prévisible au début et à la fin du son
  Afin d'attaquer le son proprement et de ne jamais entendre d'artefact

  Background:
    Given un fichier audio de 4 secondes est chargé

  Scenario: Reculer dans l'amorce
    Given la tête est à 0 seconde
    When je tourne le disque vers l'arrière d'un demi-tour
    Then la tête recule à −0,9 seconde dans l'amorce silencieuse
    And aucun son n'est produit
    When je pousse le disque vers l'avant
    Then l'attaque du son est jouée en avant

  Scenario: Dépasser la borne de l'amorce en reculant
    Given la tête est à −2 secondes
    When je continue de tourner le disque vers l'arrière
    Then la position reste à −2 secondes
    And aucun échantillon hors limites n'est lu
    And aucun bruit parasite n'est produit

  Scenario: Atteindre la fin du son moteur actif (sillon fermé)
    Given le moteur tourne à 33⅓ RPM
    When la tête atteint la fin du son
    Then le son s'arrête sans clic
    And le disque continue de tourner
    And la tête reste à la fin

  Scenario: Revenir dans le son depuis le sillon fermé
    Given la tête est bloquée à la fin depuis plusieurs tours
    When je tire le disque vers l'arrière
    Then le son est immédiatement lu à l'envers depuis la fin
    And il n'est pas nécessaire de « dérouler » les tours écoulés

  Scenario: Son très court
    Given un son de 0,2 seconde est chargé
    When je scratche le disque sur un quart de tour dans les deux sens
    Then le son est lu en avant et en arrière dans ses bornes
    And aucun clic n'est produit aux bornes
```

### 6.13 [P1] Bibliothèque minimale et glisser-déposer

```gherkin
Feature: Bibliothèque locale minimale
  En tant qu'utilisateur
  Je veux retrouver mes sons déjà importés
  Afin de les recharger sur l'une ou l'autre platine sans repasser par Fichiers

  Scenario: Consulter la bibliothèque
    Given j'ai importé trois sons
    When j'ouvre la bibliothèque
    Then le son de démonstration apparaît en tête
    And les trois sons apparaissent avec leur nom, leur durée et leur date d'import

  Scenario: Charger un son de la bibliothèque sur la platine B
    Given la bibliothèque contient "voix_funk.wav"
    When je choisis "Charger sur B" pour ce son
    Then "voix_funk.wav" est chargé sur la platine B
    And la platine A n'est pas affectée

  Scenario: Supprimer un son non chargé
    Given la bibliothèque contient "boucle.wav", qui n'est chargé sur aucune platine
    When je demande sa suppression et confirme
    Then la copie locale est supprimée
    And le son disparaît de la bibliothèque
    And le fichier original n'est pas modifié

  Scenario: Supprimer un son chargé sur une platine
    Given "boucle.wav" est chargé sur la platine A
    When je demande sa suppression
    Then l'application indique que le son est chargé sur la platine A
    When je confirme
    Then la platine A est vidée et son moteur arrêté
    And la copie locale est supprimée

  Scenario: Le son de démonstration ne peut pas être supprimé
    When j'ouvre la bibliothèque
    Then l'action "Supprimer" n'est pas proposée pour le son de démonstration

  Scenario: Retrouver la bibliothèque après relancement
    Given j'ai importé "voix_funk.wav"
    When je ferme puis relance l'application
    Then "voix_funk.wav" est toujours dans la bibliothèque

  Scenario: Déposer un fichier sur une platine
    Given l'application est ouverte sur iPad ou sur Mac
    When je fais glisser un fichier WAV valide depuis Fichiers ou le Finder sur la platine B
    Then une copie est créée et ajoutée à la bibliothèque
    And le fichier est chargé sur la platine B selon les règles de remplacement

  Scenario: Déposer un fichier non audio
    When je fais glisser un fichier PDF sur une platine
    Then le dépôt est refusé
    And la platine n'est pas modifiée
```

### 6.14 [P0] Commandes Mac

```gherkin
Feature: Scratcher sur Mac avec souris, trackpad et clavier
  En tant que DJ sur Mac
  Je veux scratcher sans écran tactile
  Afin d'utiliser ScratchApp sur mon ordinateur

  Background:
    Given l'application est ouverte sur Mac
    And un son est chargé sur la platine A
    And le moteur de la platine A tourne

  Scenario: Retenir et scratcher à la souris
    When je maintiens le clic sur le disque A
    Then le disque est retenu et le plateau continue de tourner
    When je déplace la souris en cercle dans le sens horaire puis antihoraire
    Then le son est lu en avant puis en arrière à la vitesse du geste
    When je relâche le bouton
    Then le disque rattrape la vitesse du plateau

  Scenario: Scratcher au trackpad
    When je fais défiler à deux doigts au-dessus du disque A
    Then le disque tourne dans le sens du défilement
    When j'arrête de faire défiler
    Then le disque est relâché après 80 ms sans événement

  Scenario: Couper le son au clavier pendant un scratch à la souris
    Given le crossfader est en butée B
    And je scratche le disque A à la souris
    When je maintiens la touche "F"
    Then la voie A est ouverte tant que la touche est maintenue
    When je relâche la touche "F"
    Then la voie A est de nouveau coupée
    And le scratch à la souris n'est pas interrompu

  Scenario: Piloter le transport au clavier
    When j'appuie sur "Q"
    Then le moteur de la platine A passe à STOP
    When j'appuie sur "P"
    Then le moteur de la platine B passe à START

  Scenario: Déplacer le crossfader au clavier
    Given le crossfader est au centre
    When j'appuie sur "⇧←"
    Then le crossfader est en butée A
    When j'appuie trois fois sur "→"
    Then le crossfader est à 15 % de la course vers B

  Scenario: Raccourcis inactifs pendant la saisie de texte
    Given un champ de texte a le focus
    When je tape "q"
    Then le moteur de la platine A n'est pas affecté

  Scenario: Redimensionner la fenêtre pendant un scratch
    Given je scratche le disque A à la souris
    When la fenêtre est redimensionnée
    Then le disque reste contrôlé jusqu'au relâchement du bouton
    And aucun saut de position ne se produit
```

### 6.15 [P1] Formats et fréquences

```gherkin
Feature: Prise en charge des canaux et fréquences d'échantillonnage

  Scenario Outline: Lire un son à la bonne hauteur quelle que soit sa fréquence
    Given la sortie audio fonctionne à 48 kHz
    When je charge un son enregistré à <frequence> Hz
    And j'appuie sur START avec un pitch de 0 % à 33⅓ RPM
    Then le son est joué à sa hauteur d'origine

    Examples:
      | frequence |
      | 22050     |
      | 44100     |
      | 48000     |
      | 96000     |

  Scenario: Lire un son mono
    When je charge un son mono
    Then il est audible à niveau égal sur les deux canaux

  Scenario: Lire un son multicanal
    When je charge un son 5.1
    Then il est réduit en stéréo sans saturation
```

### 6.16 [P1] Accessibilité

```gherkin
Feature: Accessibilité
  En tant qu'utilisateur de VoiceOver ou du clavier
  Je veux identifier et régler les commandes
  Afin d'utiliser l'application sans dépendre de la vue ou du tactile seul

  Scenario: Libellés VoiceOver
    Given VoiceOver est activé
    When je parcours l'écran principal
    Then chaque bouton, curseur et disque annonce un libellé et sa valeur

  Scenario: Régler le pitch par les actions d'accessibilité
    Given VoiceOver est activé et le curseur de pitch a le focus
    When je balaie vers le haut
    Then le pitch augmente de 0,1 %
    And la nouvelle valeur est annoncée

  Scenario: Navigation au clavier sur Mac
    Given l'accès clavier complet est activé sur Mac
    When j'utilise la tabulation
    Then le focus parcourt les commandes dans un ordre logique : platine A, table, platine B
```

## 7. Critères de recette V1 (P0 puis P1)

### P0

- [ ] Importer un WAV (Fichiers sur iPhone/iPad, Finder sur Mac) et obtenir un son lisible sur la platine choisie.
- [ ] Charger deux sons sur deux platines indépendantes.
- [ ] Démarrer et arrêter chaque moteur à 33⅓ et 45 RPM.
- [ ] Retenir le disque au toucher (ou au clic) sans saut de lecture, le plateau continuant de tourner (feutrine).
- [ ] Scratcher dans les deux sens, à différentes vitesses, y compris moteur arrêté.
- [ ] Relâcher le disque et retrouver la vitesse motorisée en 60 ms environ.
- [ ] Scratcher et utiliser simultanément le crossfader : au doigt sur iPhone/iPad, souris + clavier sur Mac.
- [ ] Courbe « coupure franche » : la voie s'ouvre à plein niveau en 3 % de course au plus.
- [ ] Application fonctionnelle sur macOS : compilation, tests automatisés et lancement vérifiés en CI.

### P1

- [ ] Ajuster la résistance, comparer 10 % et 90 %, retrouver le réglage au redémarrage.
- [ ] Modifier le pitch (pas de 0,1 %, remise à 0) et rappeler un point CUE, y compris disque tenu.
- [ ] Voir le repère et la forme d'onde suivre le scratch ; positionner la tête par needle drop.
- [ ] Reculer dans l'amorce et atteindre le sillon fermé sans clic.
- [ ] Recharger un son depuis la bibliothèque sur A ou B, le supprimer, dédoublonner un import identique.
- [ ] Émettre le son sur une sortie audio USB compatible et suivre un changement de périphérique.
- [ ] Gérer interruptions, arrière-plan, fichiers incorrects ou protégés et déconnexion USB sans plantage.
- [ ] Latence geste→son mesurée et consignée (objectif ≤ 20 ms) ; tampon ≤ 256 trames à 48 kHz.
- [ ] VoiceOver : toutes les commandes sont étiquetées.

## 8. Points ouverts

| ID | Sujet | Statut v2.0 |
|---|---|---|
| PO-01 | Comportement du plateau sans fichier chargé | **Clos :** le plateau peut tourner (START), sans aucun son (RM-01). |
| PO-02 | Ergonomie du crossfader sur une platine unique | **Clos :** deux platines et crossfader A↔B (SF-64 à SF-67). |
| PO-03 | Courbes et durées d'accélération et de décélération | **Clos :** pentes linéaires, démarrage 0,7 s, freinage 1,0 s, réglables de 0,1 à 5 s (SF-68). Calibrage final sur appareil. |
| PO-04 | Inertie au relâchement, geste et angle tactile | **Clos :** feutrine, rattrapage de 60 ms, modèle 5.1, RM-60 et RM-61. Calibrage final sur appareil. |
| PO-05 | Comportement en fin de sample | **Clos :** sillon fermé (RM-55). Boucle éventuelle en P2. |
| PO-06 | Ergonomie des points CUE et de leurs raccourcis | **Clos :** boutons SET CUE / CUE, raccourcis Mac (3.5). Pointeurs multiples en P2 (10.4). |
| PO-07 | Contraintes de latence audio et tactile | **Partiellement clos :** objectifs fixés (SF-78), mesure à faire sur prototype. |
| PO-08 | Compatibilité USB avec la MPC Sample et enregistrement dans Logic Pro | **Ouvert :** test sur matériel. |
| PO-09 | Arrière-plan et stratégie de session audio | **Clos :** pas d'audio en arrière-plan sur iOS/iPadOS en V1 (SF-81), catégorie de session « lecture » exclusive ; sur Mac, la lecture continue fenêtre inactive. |
| PO-10 | Design graphique et disposition des commandes | **Délégué** à la spécification UX (`docs/bmad/front-end-spec.md`), dans le cadre de 3.4. |
| PO-11 [P2] | Calibrage du souffle et des micro-craquements | Ouvert (P2). |
| PO-12 | Rechargement automatique des sons chargés au relancement | **Ouvert :** non retenu en V1 (SF-17). À trancher pour la V1.1, sans jamais relancer l'audio. |
| PO-13 | Mappage MIDI par défaut (contrôleurs de scratch du marché) | Ouvert (P2, 10.7). |
| PO-14 | Taille et contenu du son de démonstration | **Ouvert :** son généré par l'app (stab + voix synthétique « ahh ») ou ressource libre de droits embarquée ; licence à documenter. |
| PO-15 | Calibrage des constantes de résistance (2 à 35 ms) | **Ouvert :** validation sur appareil physique. |
| PO-16 | Durée maximale par son (10 min) au regard de la mémoire des appareils anciens | **Ouvert :** à réévaluer après mesure de l'empreinte mémoire. |

## 9. Journal des modifications

| Version | Date | Modification |
|---|---|---|
| 1.0 | 2026-11-12 | Première consolidation des spécifications fonctionnelles et des scénarios Gherkin de base. |
| 1.1 | 2026-11-12 | Ajout du curseur de résistance du vinyle (SF-21 à SF-24), règles RM-11 à RM-13, scénarios Gherkin 6.7 et critère de recette. |
| 1.2 | 2026-11-12 | Ajout de la lecture inversée avec scratch bidirectionnel (SF-25 à SF-28), règles RM-14 à RM-17 et scénarios Gherkin (désormais section 10.1). |
| 1.3 | 2026-11-12 | Ajout de l'effet autonome Crépitement vinyle (SF-29 à SF-34), règles RM-18 à RM-22 et scénarios Gherkin (désormais section 10.2) ; volume indépendant du disque et du crossfader. |
| 1.4 | 2026-11-12 | Classement des scénarios Gherkin P0/P1 et transfert de Reverse et Crépitement en options futures P2, en fin de document. |
| 1.5 | 2026-11-12 | Ajout de l'enregistrement local (SF-35 à SF-41), règles RM-23 à RM-28 et scénarios Gherkin 10.3 ; conservation en option future P2. |
| 1.6 | 2026-11-12 | Gestion automatique des pointeurs (SF-42 à SF-50, RM-29 à RM-35, Gherkin 10.4) en P2 ; clarification du scratch moteur arrêté en P0. |
| 1.7 | 2026-11-12 | Ajout de l'option P2 « Enregistrement microphone et banque de sons » (SF-51 à SF-59, RM-36 à RM-42, scénarios 10.5), distincte de l'enregistrement du mix ; critères de recette optionnels mis à jour. |
| 1.8 | 2026-11-12 | Décision : copie locale systématique des imports, bibliothèque physique unifiée avec les prises micro (interface P2) ; pas de signets ni de liens externes ; Gherkin sur copie, lecture hors ligne, stockage et suppression. |
| 1.9 | 2026-11-12 | Nommage des prises micro et conservation des noms importés ; menu contextuel de renommage dans la banque (SF-60 à SF-63, RM-43 à RM-46, huit scénarios Gherkin) ; pointeurs préservés par identifiant stable. |
| 2.0 | 2026-11-14 | Refonte explicite. Application renommée **ScratchApp**. Ajout de macOS (équivalences 0.3, SF-79, 6.14). **Deux platines et table de mixage** en V1 (SF-64 à SF-67). Feutrine et couple moteur (SF-68), repère, forme d'onde et needle drop (SF-69 à SF-71), amorce et sillon fermé (SF-72, RM-55), glisser-déposer, bibliothèque minimale, dédoublonnage et démo (SF-73 à SF-76), qualité audio et latence (SF-77, SF-78), formats, cycle de vie, sortie indisponible et accessibilité (SF-80 à SF-83). Règles RM-50 à RM-61. Renumérotation des règles de copie v1.8 en RM-47 à RM-49 (collision avec RM-43 à RM-46). Background de 6.3 scindé en règles « moteur actif » et « moteur arrêté ». Points ouverts PO-01 à PO-06 et PO-09 clos ; PO-12 à PO-16 ajoutés. Nommage harmonisé des enregistrements de mix (`MIX_…`). Section 10.7 (nouvelles options P2). |

> Les prochains ajouts et corrections devront garder les identifiants SF, RM, PO et E stables, sauf refonte explicite.

---

## 10. Options futures — priorité P2 (hors V1)

Ces fonctionnalités sont **documentées mais non exigées** pour la première version. Leur développement et leur recette seront planifiés ultérieurement. Les identifiants SF et RM d'origine sont conservés.

> **Note v2.0 :** chaque option P2 s'applique **par platine** (A et B) lorsqu'elle concerne le disque (reverse, pointeurs), et **à la sortie de la table de mixage** lorsqu'elle concerne le mix (crépitement, REC mix). Sur Mac, « Fichiers » se lit « Finder », « iPhone/iPad » se lit « Mac » et « interruption de session audio » se lit « changement de configuration audio » (tableau 0.3).

### 10.1 Reverse motorisé — P2

**Interface future :** interrupteur REVERSE ON/OFF, un par platine. La lecture automatique peut aller en sens inverse sans supprimer le scratch tactile bidirectionnel ni les réglages existants.

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
- **RM-22 :** l'interruption audio iOS/iPadOS (ou le changement de configuration audio sur Mac) interrompt aussi le crépitement ; aucune reprise spontanée après une interruption ni au lancement de l'application.
- **Amendement v2.0 de RM-01 :** lorsque le crépitement sera implémenté, RM-01 devient « sans son chargé, une platine n'émet aucun son de fichier » : le crépitement activé explicitement reste audible sans fichier (SF-32).

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

**Interface future :** bouton **REC** accessible sur la table de mixage, avec état visuel « Enregistrement » et compteur de durée. Un appui démarre immédiatement la capture, un second appui la termine et sauvegarde le résultat. La source capturée est le **mix de sortie de la table de mixage** (platines A et B), comprenant les samples et les manipulations (scratch, crossfader, faders de voie, pitch), ainsi que les effets activés lorsque ceux-ci seront implémentés. Les sons provenant d'autres applications ou du microphone ne sont pas enregistrés.

**Exigences SF-35 à SF-41 :**

| ID | Exigence | Résultat attendu |
|---|---|---|
| SF-35 | Bouton REC | Un premier appui sur REC commence immédiatement l'enregistrement du mix audio de l'application ; le bouton change d'état et le compteur démarre. Aucun écran de configuration préalable. |
| SF-36 | Arrêt et finalisation | Un second appui sur REC arrête la capture et finalise un fichier audio exploitable ; une confirmation affiche son nom et son emplacement. Le disque peut continuer à jouer. |
| SF-37 | Dossier local par défaut | Enregistrer dans le dossier **Enregistrements** de l'espace Documents de l'application, sur l'appareil courant ; le dossier est créé si nécessaire et rendu accessible dans **Fichiers > Sur mon iPhone / Sur mon iPad > ScratchApp** (clés `UIFileSharingEnabled` et `LSSupportsOpeningDocumentsInPlace`) ; sur Mac, via le menu « Afficher les enregistrements dans le Finder ». Aucun export manuel n'est nécessaire pour la sauvegarde locale. |
| SF-38 | Nom et format | **[Corrigé v2.0]** Attribuer automatiquement un nom unique horodaté `MIX_AAAAMMJJ_HHMMSS.wav` (heure locale), par exemple `MIX_20261112_102400.wav`, avec suffixe numérique en cas de collision — convention harmonisée avec `REC_…` des prises micro (SF-61). Format WAV PCM par défaut ; ses paramètres (fréquence/bit depth) seront précisés dans les spécifications techniques. |
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
  Afin de conserver mes scratchs sur mon iPhone, mon iPad ou mon Mac

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

  Scenario: Retrouver l'enregistrement dans le Finder sur Mac
    Given un enregistrement a été sauvegardé avec succès sur Mac
    When je choisis le menu "Afficher les enregistrements dans le Finder"
    Then une fenêtre du Finder s'ouvre sur le dossier "Enregistrements"
    And le fichier "MIX_AAAAMMJJ_HHMMSS.wav" y figure

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
| SF-43 | Identification fiable | Identifier le même contenu audio avec une empreinte numérique stable des octets (SHA-256, RM-58), indépendamment du nom ou du chemin ; éviter de confondre deux fichiers distincts portant le même nom. |
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

**Objectif :** permettre de créer un nouveau sample en enregistrant la voix, un instrument ou un bruit avec le microphone intégré de l’iPhone/iPad/Mac (ou une entrée audio sélectionnée par le système), puis de charger cet enregistrement directement sur la platine virtuelle pour le scratcher. Cette fonction est **distincte** de l’option 10.3 « Enregistrement audio local », qui capture la sortie/mix de la platine.

**Note v2.0 :** la « Banque de sons » P2 **étend la bibliothèque minimale V1** (SF-74) : même stockage, même index, mêmes identifiants (RM-58). Le dédoublonnage par contenu (SF-75) est déjà actif en V1.

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

**Point ouvert P2 (partiellement clos v2.0) :** la politique anti-doublons fondée sur le contenu est décidée (SF-75, RM-58). Reste à définir la suppression des métadonnées (pointeurs) associées à une copie supprimée. La règle reste une copie locale, sans référencement distant.

**Point ouvert P2 :** préciser les cas où l'utilisateur tente de capter le microphone pendant que le moteur de scratch produit du son (monitoring, écoute au casque, prévention du larsen). Par défaut, aucune écoute micro amplifiée ne sera activée sans demande explicite.

### 10.6 Critères de recette futurs (non bloquants pour la V1)

- [ ] Reverse motorisé : transition sans saut, scratch avant/arrière toujours possible, reprise en sens inverse après relâchement.
- [ ] Crépitement vinyle : activation autonome, volume indépendant, persistance pendant scratch/STOP/reverse, extinction sans clic.
- [ ] Enregistrement : premier appui REC démarre, second appui finalise un WAV dans le dossier local de l’application ; les scratchs sont capturés et les erreurs de stockage sont correctement signalées.
- [ ] Pointeurs : ajout/suppression/rappel, pagination, restauration automatique par empreinte du fichier et conservation intégrale de l’état moteur.
- [ ] Banque de sons locale : imports copiés et prises micro réunis, ouverture hors ligne, REC/STOP, erreur stockage et suppression protégée sans toucher à l’original externe.
- [ ] Nommage et renommage : nom original des imports, `REC_AAAAMMJJ_HHMMSS.wav` pour le micro, suffixes anti-collision, menu Renommer depuis la banque, conservation des pointeurs.
- [ ] Contrôleur MIDI (E-10) : disques, crossfader et transport pilotables ; MIDI learn.

### 10.7 Nouvelles options P2 proposées en v2.0

| ID | Option | Description |
|---|---|---|
| E-10 | Contrôleur MIDI | Piloter les disques (jog wheels), le crossfader et le transport depuis un contrôleur DJ USB/Bluetooth MIDI, avec mappage apprenable (MIDI learn) et mappage par défaut pour les contrôleurs de scratch courants (PO-13). Sur Mac, c'est le seul moyen d'avoir deux mains sur deux disques. |
| E-11 | Plages de pitch étendues | Plages ±16 % et ±50 % au choix, en plus de ±8 % ; bouton de remise à zéro. |
| — | Retour haptique | Impulsion légère à chaque tour de disque et au passage du repère (iPhone), si le matériel le permet. |
| — | Effet « power down » | Freinage très long (jusqu'à 5 s) déclenché par un geste dédié. |
| — | Boucle en fin de son | Alternative au sillon fermé (PO-05) : bouclage du son en fin de lecture. |
| — | Rechargement de session | Recharger au lancement les sons des platines A et B (PO-12), toujours sans lecture automatique. |
