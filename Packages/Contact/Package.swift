// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Contact",
    defaultLocalization: "ar",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "Contact", targets: ["Contact"])
    ],
    targets: [
        .target(name: "Contact")
    ]
)
