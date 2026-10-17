// swift-tools-version: 6.0
import PackageDescription

// A small host-side test package for the model/store and drawing serializer.
// The shipping iPad application is built from MicaDesk.xcodeproj.
let package = Package(
    name: "MicaDeskCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MicaDesk", targets: ["MicaDesk"])
    ],
    targets: [
        .target(
            name: "MicaDesk",
            path: "MicaDesk",
            exclude: [
                "Assets.xcassets",
                "MicaDeskApp.swift",
                "Views",
                "Support/PreviewData.swift",
                "Support/ToolPickerController.swift"
            ],
            sources: [
                "Models/Card.swift",
                "Data/CardStore.swift",
                "Support/DrawingPersistence.swift"
            ]
        ),
        .testTarget(
            name: "MicaDeskTests",
            dependencies: ["MicaDesk"],
            path: "MicaDeskTests"
        )
    ]
)

