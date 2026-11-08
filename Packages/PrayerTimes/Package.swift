// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PrayerTimes",
    defaultLocalization: "ar",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "PrayerTimes", targets: ["PrayerTimes"])
    ],
    targets: [
        .target(name: "PrayerTimes")
    ]
)
