// swift-tools-version: 6.2
import PackageDescription

// Accès au NAS en SMB depuis l'iPhone (EF-71, EF-72, EF-87), via AMSMB2 (LGPL 2.1, usage personnel).
// Séparé de SeanceKit pour que le moteur reste sans dépendance externe.
let package = Package(
    name: "SeanceNAS",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SeanceNAS", targets: ["SeanceNAS"]),
    ],
    dependencies: [
        .package(path: "../SeanceKit"),
        .package(url: "https://github.com/amosavian/AMSMB2", exact: "4.0.3"),
    ],
    targets: [
        .target(
            name: "SeanceNAS",
            dependencies: [
                .product(name: "SeanceKit", package: "SeanceKit"),
                .product(name: "AMSMB2", package: "AMSMB2"),
            ]
        ),
    ]
)
