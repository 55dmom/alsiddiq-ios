// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Adhkar",
    defaultLocalization: "ar",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "Adhkar", targets: ["Adhkar"])
    ],
    targets: [
        .target(name: "Adhkar", resources: [.process("Resources")])
    ]
)
