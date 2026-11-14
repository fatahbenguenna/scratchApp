import ScratchCore

/// Tampon de sortie demandé au matériel (#91 ; SF-78 ; D-15, D-54), en logique pure.
///
/// Premier levier du calibrage de la latence geste→son : **128 trames** (≈ 2,7 ms à 48 kHz) quand le
/// matériel les accorde, et **256 trames** en repli (`TurntableConstants.preferredBufferFrames`,
/// plafond de SF-78). Mesures de la sonde en régime appris (#92), à 48 kHz, hors latence du
/// périphérique :
///
/// | Affichage | 256 trames | 128 trames | Objectif D-15 |
/// |---|---|---|---|
/// | 120 Hz | 19,0 ms | 15,2 ms | ≤ 20 ms |
/// | 60 Hz | 27,3 ms | 23,1 ms | ≤ 30 ms |
///
/// Un tampon plus court réduit à la fois le tampon de sortie et le retard appris du rejeu du doigt :
/// les touches sont vues plus tôt par le fil audio.
enum OutputBufferPolicy {
    /// Tampon visé.
    static let preferredFrames = 128
    /// Repli, et plafond de SF-78.
    static let fallbackFrames = TurntableConstants.preferredBufferFrames

    /// Négocie le tampon. `request` demande un nombre de trames au matériel et renvoie le tampon
    /// effectif relu, ou `nil` si la demande échoue. 128 trames sont demandées d'abord ; tout tampon
    /// accordé jusqu'à 256 trames est gardé (un périphérique dont le minimum vaut 192 trames reste à
    /// 192). Sinon (demande refusée, ou tampon accordé au-delà de 256 trames), 256 trames sont
    /// demandées. Renvoie le tampon effectif obtenu.
    @discardableResult
    static func negotiate(_ request: (Int) -> Int?) -> Int? {
        if let granted = request(preferredFrames), granted <= fallbackFrames { return granted }
        return request(fallbackFrames)
    }
}
