/// Arguments de lancement de l'application (story 6.2).
///
/// `--demo-scene` est réservé à la CI : la capture d'écran montre l'app réelle, avec le son de
/// démonstration chargé sur A et B et la platine B en lecture. Sans cet argument, aucun son n'est
/// chargé ni joué de lui-même (RM-01, RM-10, SF-76). `ScratchAppMain` ne le lit que dans les builds
/// Debug, ceux de la CI.
public struct LaunchOptions: Equatable, Sendable {
    public static let demoSceneArgument = "--demo-scene"

    /// Scène de démonstration de la CI.
    public var demoScene: Bool

    public init(demoScene: Bool = false) {
        self.demoScene = demoScene
    }

    /// - Parameter arguments: `CommandLine.arguments` ; le premier élément, le chemin de l'exécutable,
    ///   est ignoré.
    public init(arguments: [String]) {
        self.init(demoScene: arguments.dropFirst().contains(Self.demoSceneArgument))
    }
}
