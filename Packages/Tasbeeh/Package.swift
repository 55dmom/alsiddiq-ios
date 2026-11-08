// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tasbeeh",
    defaultLocalization: "ar",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "Tasbeeh", targets: ["Tasbeeh"])
    ],
    targets: [
        .target(name: "Tasbeeh", resources: [.process("Resources")])
    ]
)
