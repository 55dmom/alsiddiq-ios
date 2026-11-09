// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Hifz",
    defaultLocalization: "ar",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "Hifz", targets: ["Hifz"])
    ],
    targets: [
        .target(name: "Hifz", resources: [.process("Resources")])
    ]
)
