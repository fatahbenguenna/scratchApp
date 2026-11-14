/// Valeur commandée par l'interface, affichée jusqu'à ce qu'un instantané du moteur la confirme
/// (bug #57 ; architecture §5.2, ADR-12).
///
/// Quand l'hôte audio rend le son, une commande n'est appliquée qu'au rendu suivant (5 à 11 ms) :
/// l'image qui suit l'envoi lit souvent un instantané antérieur. Sans ce maintien, une mise à jour
/// optimiste serait aussitôt écrasée et la commande clignoterait (START/STOP, faders, crossfader).
///
/// La valeur commandée est affichée tant que l'instantané ne montre pas la même valeur, au plus
/// `timeout` secondes après la dernière commande ; au-delà, l'instantané fait foi (commande refusée
/// ou bornée par le moteur). Logique pure, testée sans moteur.
struct CommandedValue<Value: Equatable> {
    /// Délai de confirmation : bien plus long que deux périodes de rendu (≤ 23 ms).
    static var timeout: Double { 0.1 }

    private(set) var pending: Value?
    private var deadline = 0.0

    /// Une commande vient d'être acceptée par le moteur.
    mutating func command(_ value: Value, at now: Double) {
        pending = value
        deadline = now + Self.timeout
    }

    /// Valeur à afficher pour la valeur `published` de l'instantané : la commande en attente, ou
    /// l'instantané dès qu'il la confirme ou que le délai est écoulé.
    mutating func resolve(_ published: Value, at now: Double) -> Value {
        guard let pending else { return published }
        if published == pending || now >= deadline {
            self.pending = nil
            return published
        }
        return pending
    }
}
