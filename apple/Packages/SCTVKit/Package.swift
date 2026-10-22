// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SCTVKit",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "SCTVCore", targets: ["SCTVCore"]),
        .library(name: "SCTVData", targets: ["SCTVData"]),
        .library(name: "SCTVDownloads", targets: ["SCTVDownloads"]),
        .library(name: "SCTVMedia", targets: ["SCTVMedia"]),
        .library(name: "SCTVFeatures", targets: ["SCTVFeatures"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
        .package(url: "https://github.com/kean/Nuke.git", exact: "13.2.0"),
    ],
    targets: [
        .target(name: "SCTVCore"),
        .target(
            name: "SCTVData",
            dependencies: ["SCTVCore", .product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "SCTVMedia", dependencies: ["SCTVCore"]),
        .target(name: "SCTVDownloads", dependencies: ["SCTVCore"]),
        .target(
            name: "SCTVFeatures",
            dependencies: [
                "SCTVCore", .product(name: "Nuke", package: "Nuke"),
                .product(name: "NukeUI", package: "Nuke"),
            ]),
        .testTarget(name: "SCTVFeaturesTests", dependencies: ["SCTVCore", "SCTVFeatures"]),
        .testTarget(
            name: "SCTVDataTests", dependencies: ["SCTVCore", "SCTVData"],
            resources: [.copy("Fixtures")]),
        .testTarget(
            name: "SCTVMediaTests", dependencies: ["SCTVCore", "SCTVMedia"],
            resources: [.copy("Fixtures")]),
        .testTarget(
            name: "SCTVDownloadsTests",
            dependencies: [
                "SCTVCore", "SCTVData", "SCTVDownloads",
                .product(name: "GRDB", package: "GRDB.swift"),
            ], resources: [.copy("Fixtures")]),
        .testTarget(
            name: "SCTVCoreTests",
            dependencies: ["SCTVCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
