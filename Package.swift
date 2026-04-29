// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clipo",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Clipo", targets: ["Clipo"])
    ],
    targets: [
        .executableTarget(
            name: "Clipo",
            path: "Sources/Clipo",
            resources: [],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Network")
            ]
        )
    ]
)
