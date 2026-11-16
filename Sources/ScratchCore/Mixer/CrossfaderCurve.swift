import Foundation

/// Courbe du crossfader (spec 5.2, SF-66, D-02) : fonction pure, utilisable par le rendu et par
/// l'UI (dessin de la courbe dans les réglages, UX §5.13).
///
/// - douce (`curve = 0`) : `gA = cos(x·π/2)`, `gB = sin(x·π/2)` (puissance constante, −3 dB au centre) ;
/// - coupure franche (`curve = 1`) : `gB = min(1, x / w)`, `gA = min(1, (1 − x) / w)`, `w = 0,03` ;
/// - intermédiaire : largeur de cut-in `w = lerp(1 ; 0,03 ; curve)` et, pour chaque voie, le plus
///   grand des gains de la famille douce et de la famille franche de largeur `w`.
///
/// Propriétés (story 1.4 CA 2) : chaque gain est monotone en `x` (maximum de deux fonctions
/// monotones de même sens) et croît avec `curve` à `x` fixé (la famille franche s'ouvre quand `w`
/// diminue), de la courbe douce exacte à `curve = 0` (la corde reste sous l'arc) à la coupure
/// franche exacte à `curve = 1` (la pente 1/0,03 dépasse celle de l'arc). Le changement de courbe est
/// donc monotone et perceptible (5.2).
public enum CrossfaderCurve {
    /// Gains des voies A et B pour une position `x` (0 = butée A, 1 = butée B, **après** inversion
    /// hamster éventuelle) et une courbe `curve` (0 = douce, 1 = coupure franche), dans 0…1. Les
    /// valeurs hors plage sont ramenées dans 0…1 ; une valeur non finie vaut la valeur par défaut.
    public static func gains(position x: Double, curve: Double) -> (a: Double, b: Double) {
        let position = x.clamped(to: 0...1, fallback: TurntableConstants.defaultCrossfader)
        let shape = curve.clamped(to: 0...1, fallback: TurntableConstants.defaultCrossfaderCurve)
        let width = cutInWidth(curve: shape)
        let hardA = min(1, (1 - position) / width)
        let hardB = min(1, position / width)
        // sin((1 − x)·π/2) = cos(x·π/2), exact 0 and 1 at the stops.
        let softA = sin((1 - position) * Double.pi / 2)
        let softB = sin(position * Double.pi / 2)
        return (a: max(softA, hardA), b: max(softB, hardB))
    }

    /// Largeur de cut-in `w = lerp(1 ; 0,03 ; curve)` : course, depuis la butée opposée, au bout de
    /// laquelle une voie atteint le plein niveau dans la famille franche (UX §5.12). Publique pour les
    /// repères de cut-in du crossfader de l'interface (#75).
    public static func cutInWidth(curve: Double) -> Double {
        (1 - curve) + curve * TurntableConstants.crossfaderCutInWidth // exact at both ends
    }
}
