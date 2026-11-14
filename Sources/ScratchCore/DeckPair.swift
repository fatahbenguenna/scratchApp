/// Une valeur par platine (A et B), sans allocation.
///
/// Type valeur de taille fixe : utilisable dans l'instantané du moteur (`EngineSnapshot`), qui
/// ne doit contenir aucun tableau dynamique (règle temps réel, architecture §6).
public struct DeckPair<Value> {
    public var a: Value
    public var b: Value

    public init(a: Value, b: Value) {
        self.a = a
        self.b = b
    }

    public init(repeating value: Value) {
        self.init(a: value, b: value)
    }

    public subscript(deck: DeckID) -> Value {
        get {
            switch deck {
            case .a: return a
            case .b: return b
            }
        }
        set {
            switch deck {
            case .a: a = newValue
            case .b: b = newValue
            }
        }
    }

    public func map<T>(_ transform: (Value) throws -> T) rethrows -> DeckPair<T> {
        DeckPair<T>(a: try transform(a), b: try transform(b))
    }
}

extension DeckPair: Equatable where Value: Equatable {}
extension DeckPair: Hashable where Value: Hashable {}
extension DeckPair: Sendable where Value: Sendable {}
extension DeckPair: Codable where Value: Codable {}
