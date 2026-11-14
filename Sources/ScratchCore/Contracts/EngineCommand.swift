/// Commande envoyée par le fil principal au moteur audio (PRD 5.3 point 2 ; architecture §5.1).
///
/// Conventions communes :
/// - **Angles** en radians, **cumulés** (dépliés, sans saut à ±π), positifs dans le sens horaire,
///   c'est-à-dire le sens de lecture normal. Le dépliage est fait côté UI par `GestureAngleTracker`.
/// - **Temps** en secondes sur une horloge **monotone** fournie par l'appelant (`UITouch.timestamp`,
///   `NSEvent.timestamp`, `ProcessInfo.systemUptime`) : la même horloge pour toute la durée d'un geste.
/// - **Valeurs normalisées** : pitch en fraction (−0,08…0,08), résistance, crossfader, courbe et
///   faders de voie dans 0…1. Le moteur borne chaque valeur et ignore les valeurs non finies.
/// - Aucune commande d'une platine ne modifie l'autre (RM-51).
public enum EngineCommand: Equatable, Sendable {
    // MARK: Transport (par platine)

    /// Charge un son. La platine revient à l'état initial (SF-03, SF-15) : tête à 0 s, moteur
    /// arrêté, CUE effacé, disque relâché. L'ancien clip part dans la file de retour.
    case load(DeckID, AudioClip)
    /// Vide la platine (suppression d'un son chargé, 6.13) : moteur arrêté, silence (RM-01).
    case unload(DeckID)
    /// START (`true`) ou STOP (`false`), avec les rampes de démarrage et de freinage (SF-04, SF-05).
    case motor(DeckID, on: Bool)
    /// Vitesse nominale 33⅓ ou 45 RPM. Moteur en marche, le plateau rejoint la nouvelle vitesse
    /// progressivement (6.2).
    case speed(DeckID, TurntableSpeed)
    /// Pitch en fraction de la vitesse nominale, borné à `TurntableConstants.pitchRange` (SF-11).
    /// La quantification au pas de 0,1 % est faite par l'UI.
    case pitch(DeckID, Double)

    // MARK: Jeu (par platine)

    /// Résistance du vinyle 0 (léger) … 1 (lourd), modifiable pendant le scratch (SF-21 à SF-23).
    case resistance(DeckID, Double)
    /// Début d'un geste qui a commencé **sur** le disque (RM-60). `angle` est l'angle cumulé du
    /// doigt ; la prise est relative (le disque ne saute pas). Ignoré si le disque est déjà tenu.
    case touchBegan(DeckID, angle: Double, time: Double)
    /// Nouvelle position du doigt. Envoyer **chaque** touche regroupée (coalesced), dans l'ordre
    /// chronologique ; les temps non croissants sont ignorés. Ignoré si le disque n'est pas tenu.
    /// `predicted` marque une touche prédite (`UIEvent.predictedTouches`) : provisoire, remplacée par
    /// les touches réelles suivantes (PRD 1.2 critère 6, NFR1). Son exploitation par le moteur
    /// (comblement des famines du rejeu, ADR-07) est calibrée en story 1.2 ; d'ici là, elle est ignorée.
    case touchMoved(DeckID, angle: Double, time: Double, predicted: Bool = false)
    /// Fin du geste (relâchement, ou toucher annulé par le système : RM-60).
    case touchEnded(DeckID, time: Double)
    /// SET CUE : mémorise la position courante de la tête (SF-13).
    case setCue(DeckID)
    /// CUE : ramène la tête au CUE, ou à 0 s sans CUE, sans changer l'état du moteur, y compris
    /// disque tenu (SF-13, 6.6). Saut lissé sur 5 ms.
    case recallCue(DeckID)
    /// Needle drop : place la tête à `seconds`, bornée à [−2 s ; durée], sans changer l'état du
    /// moteur. **Ignoré tant que le disque est tenu** (SF-71). Saut lissé sur 5 ms.
    case seek(DeckID, seconds: Double)

    // MARK: Réglages moteur (les deux platines)

    /// Durée de démarrage, bornée à `motorDurationRange` (SF-68).
    case startDuration(Double)
    /// Durée de freinage, bornée à `motorDurationRange` (SF-68).
    case brakeDuration(Double)
    /// Temps de rattrapage de la feutrine (95 % de la vitesse du plateau), borné à
    /// `slipmatCatchUpRange` (SF-68, arbitrage IC-03).
    case slipmatCatchUp(Double)

    // MARK: Table de mixage

    /// Position du crossfader : 0 = butée A, 1 = butée B (avant inversion hamster).
    case crossfader(Double)
    /// Courbe du crossfader : 0 = douce (puissance constante), 1 = coupure franche (SF-66, 5.2).
    case crossfaderCurve(Double)
    /// Inversion hamster (SF-67) ; bascule lissée sur 5 ms.
    case hamster(Bool)
    /// Fader de voie 0…1 (SF-65).
    case lineFader(DeckID, Double)
    /// Coupure momentanée (3.5) : tant que `open` est vrai, la voie ignore le crossfader
    /// (gain = fader de voie × 1, arbitrage IC-06). Montée ≤ 1 ms.
    case momentaryCut(DeckID, open: Bool)

    // MARK: Système

    /// Interruption, arrière-plan iOS, perte du périphérique : chaque moteur passe à STOP
    /// **sans rampe**, positions conservées (RM-56, SF-18). Un disque tenu reste tenu.
    case stopAllMotors
    /// Fréquence de la sortie audio, en Hz. Aucun redécodage : le rendu rééchantillonne à la volée.
    case outputSampleRate(Double)
}
