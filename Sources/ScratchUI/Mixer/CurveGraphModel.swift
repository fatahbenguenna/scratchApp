import ScratchCore

/// Mini-graphique des gains A et B du réglage de courbe (UX §5.13 ; #75), en calcul pur.
///
/// Les gains viennent de `CrossfaderCurve.gains` (ScratchCore), la fonction du rendu : le graphique
/// montre exactement ce que l'on entend. L'abscisse suit l'écran, de la butée gauche à la butée
/// droite : avec le hamster, la voie B est pleine à gauche, comme les lettres du crossfader.
enum CurveGraphModel {
    struct Sample: Equatable {
        /// Position à l'écran, 0 (butée gauche) … 1 (butée droite).
        let x: Double
        let gainA: Double
        let gainB: Double
    }

    /// `count` + 1 échantillons régulièrement espacés de la butée gauche à la butée droite.
    static func samples(curve: Double, hamster: Bool, count: Int) -> [Sample] {
        let steps = max(count, 1)
        return (0...steps).map { index in
            let x = Double(index) / Double(steps)
            let gains = CrossfaderCurve.gains(position: hamster ? 1 - x : x, curve: curve)
            return Sample(x: x, gainA: gains.a, gainB: gains.b)
        }
    }
}
