// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Duas",
    defaultLocalization: "ar",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "Duas", targets: ["Duas"])
    ],
    targets: [
        .target(name: "Duas", resources: [.process("Resources")])
    ]
)
