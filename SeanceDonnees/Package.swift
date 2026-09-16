// swift-tools-version: 6.2
import PackageDescription

// Modèle SwiftData de Séance. Les macros @Model ne sont livrées qu'avec Xcode :
// ce paquet se compile et se teste dans Xcode, pas avec les seules Command Line Tools.
let package = Package(
    name: "SeanceDonnees",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SeanceDonnees", targets: ["SeanceDonnees"]),
    ],
    dependencies: [
        .package(path: "../SeanceKit"),
    ],
    targets: [
        .target(
            name: "SeanceDonnees",
            dependencies: [.product(name: "SeanceKit", package: "SeanceKit")]
        ),
        .testTarget(name: "SeanceDonneesTests", dependencies: ["SeanceDonnees"]),
    ]
)
