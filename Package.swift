// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DesktopProfileManager",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "DesktopProfileManager",
            path: "Sources/DesktopProfileManager"
        ),
        .testTarget(
            name: "DesktopProfileManagerTests",
            dependencies: ["DesktopProfileManager"],
            path: "Tests/DesktopProfileManagerTests"
        )
    ]
)
