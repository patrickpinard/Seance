// swift-tools-version: 6.2
import PackageDescription

// Moteur de Séance sans SwiftData : il se compile et se teste avec les seuls
// Command Line Tools (voir outils/tester.sh). Le modèle persistant vit dans SeanceDonnees.
let package = Package(
    name: "SeanceKit",
    platforms: [.iOS(.v26), .macOS(.v26), .tvOS(.v26)],
    products: [
        .library(name: "SeanceKit", targets: ["SeanceKit"]),
    ],
    targets: [
        .target(name: "SeanceKit"),
        .testTarget(
            name: "SeanceKitTests",
            dependencies: ["SeanceKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
