// swift-tools-version:5.10
// ScratchKit — cœur multi-plateforme de ScratchApp.
//
// Modules :
//   ScratchCore    : physique des platines, rendu DSP, table de mixage (Swift pur, testable sous Linux)
//   ScratchLibrary : bibliothèque locale, copie des imports, empreinte SHA-256, préférences (Foundation, Linux OK)
//   ScratchAudio   : moteur AVAudioEngine, décodage, session audio, self-test (Apple uniquement)
//   ScratchUI      : vues SwiftUI et modèles de présentation (Apple uniquement)
import PackageDescription

var products: [Product] = [
    .library(name: "ScratchCore", targets: ["ScratchCore"]),
    .library(name: "ScratchLibrary", targets: ["ScratchLibrary"]),
]

var targets: [Target] = [
    .target(
        name: "ScratchCore",
        dependencies: [.product(name: "Atomics", package: "swift-atomics")]
    ),
    .target(
        name: "ScratchLibrary",
        dependencies: ["ScratchCore"]
    ),
    .testTarget(name: "ScratchCoreTests", dependencies: ["ScratchCore"]),
    .testTarget(name: "ScratchLibraryTests", dependencies: ["ScratchLibrary"]),
]

#if !os(Linux)
products += [
    .library(name: "ScratchAudio", targets: ["ScratchAudio"]),
    .library(name: "ScratchUI", targets: ["ScratchUI"]),
]
targets += [
    .target(name: "ScratchAudio", dependencies: ["ScratchCore", "ScratchLibrary"]),
    .target(name: "ScratchUI", dependencies: ["ScratchCore", "ScratchLibrary", "ScratchAudio"]),
    .testTarget(name: "ScratchAudioTests", dependencies: ["ScratchAudio"]),
]
#endif

let package = Package(
    name: "ScratchKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: products,
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
    ],
    targets: targets
)
