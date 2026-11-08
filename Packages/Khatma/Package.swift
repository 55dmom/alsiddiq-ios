// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Khatma",
    defaultLocalization: "ar",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "Khatma", targets: ["Khatma"])
    ],
    targets: [
        .target(name: "Khatma", resources: [.process("Resources")])
    ]
)
