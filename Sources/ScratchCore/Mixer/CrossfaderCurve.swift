/// Courbe du crossfader (spec 5.2, SF-66) : fonction pure, utilisable par le rendu et par l'UI
/// (dessin de la courbe dans les réglages).
///
/// **Squelette (story EP1, James) : renvoie des gains nuls.** À implémenter :
/// - douce (`curve = 0`) : `gA = cos(x·π/2)`, `gB = sin(x·π/2)` ;
/// - coupure franche (`curve = 1`) : `gB = min(1, x / w)`, `gA = min(1, (1 − x) / w)`, `w = 0,03` ;
/// - intermédiaire : `w = lerp(1, 0,03, curve)` et interpolation de forme monotone ;
/// - tableau de valeurs de 6.10 à 0,05 près.
public enum CrossfaderCurve {
    /// Gains des voies A et B pour une position `x` (0 = butée A, 1 = butée B, **après** inversion
    /// hamster éventuelle) et une courbe `curve` (0 = douce, 1 = coupure franche), dans 0…1.
    public static func gains(position x: Double, curve: Double) -> (a: Double, b: Double) {
        (a: 0, b: 0)
    }
}
