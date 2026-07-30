// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "twig",
    platforms: [.macOS("15.0")],
    targets: [
        .target(name: "TwigCore", path: "Sources/TwigCore"),
        .executableTarget(name: "twig", dependencies: ["TwigCore"], path: "Sources/twig-cli"),
        .executableTarget(name: "TwigApp", dependencies: ["TwigCore"], path: "Sources/TwigApp"),
        .testTarget(name: "TwigCoreTests", dependencies: ["TwigCore"], path: "Tests/TwigCoreTests"),
    ]
)
