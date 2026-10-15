// swift-tools-version: 6.0
import PackageDescription

// A small host-side test package for the model/store and drawing serializer.
// The shipping iPad application is built from InkStack.xcodeproj.
let package = Package(
    name: "InkStackCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "InkStack", targets: ["InkStack"])
    ],
    targets: [
        .target(
            name: "InkStack",
            path: "InkStack",
            exclude: [
                "Assets.xcassets",
                "InkStackApp.swift",
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
            name: "InkStackTests",
            dependencies: ["InkStack"],
            path: "InkStackTests"
        )
    ]
)

