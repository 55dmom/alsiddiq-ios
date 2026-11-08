// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AsmaAllah",
    defaultLocalization: "ar",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "AsmaAllah", targets: ["AsmaAllah"])
    ],
    targets: [
        .target(name: "AsmaAllah", resources: [.process("Resources")])
    ]
)
