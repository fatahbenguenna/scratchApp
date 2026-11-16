/// Leviers de latence du rejeu du doigt (#91 ; SF-78 ; D-15, D-16, D-54, D-56), **désactivés par
/// défaut** : le PO décide de leur mise en service. Ils s'ajoutent au tampon de 128 trames (levier 1) et
/// au rejeu ancré sur l'horloge estimée (#123).
///
/// Effet sur la latence de référence de D-56 (sonde de #122, moyenne sur 8 phases, régime appris,
/// tampon compris, sans le périphérique), à 48 kHz et 128 trames, avec #123 :
///
/// | Levier | 120 Hz | 60 Hz |
/// |---|---|---|
/// | aucun | 17,0 ms | 25,0 ms |
/// | marge réduite | 16,1 ms | 24,0 ms |
/// | touches prédites, une touche d'avance (4,2 ms) | 13,4 ms | 21,3 ms |
/// | touches prédites, deux touches d'avance (8,3 ms) | 11,7 ms | 19,2 ms |
/// | marge réduite et touches prédites (une touche) | 13,0 ms | 20,6 ms |
///
/// Les touches prédites sont mesurées dans le meilleur cas : un doigt à vitesse constante, prédit
/// exactement. Leur gain réel dépend de l'horizon et de la justesse des prédictions du système, à
/// mesurer sur appareil.
public struct ReplayLatencyOptions: Equatable, Sendable {
    /// Levier 2 : marge visée du rejeu de 0,5 ms au lieu de 1,5 ms. Gain d'environ 0,9 ms en moyenne ;
    /// risque de famine (disque figé un instant) sous la gigue réelle des images.
    public var reducedMargin: Bool
    /// Levier 3 : les touches prédites (`touchMoved(predicted: true)`) comblent l'attente entre deux
    /// livraisons (SF-78). Une prédiction n'est suivie que dans le sens du dernier mouvement réel, sans
    /// aller plus vite que lui, sans dépasser l'arrêt d'un mouvement qui ralentit, et sur 8,3 ms au
    /// plus ; elle est remplacée par les touches réelles dès leur arrivée.
    public var predictedTouches: Bool

    public init(reducedMargin: Bool = false, predictedTouches: Bool = false) {
        self.reducedMargin = reducedMargin
        self.predictedTouches = predictedTouches
    }

    /// Réglage livré : aucun levier.
    public static let standard = ReplayLatencyOptions()
}
