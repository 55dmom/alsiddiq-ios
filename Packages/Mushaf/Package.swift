// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Mushaf",
    defaultLocalization: "ar",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "Mushaf", targets: ["Mushaf"])
    ],
    targets: [
        .target(name: "Mushaf", resources: [.process("Resources")])
    ]
)
