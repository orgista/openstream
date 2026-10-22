// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenStreamApple",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .tvOS(.v18),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "OpenStreamApple", targets: ["OpenStreamApple"]),
    ],
    dependencies: [
        .package(url: "https://github.com/amosavian/AMSMB2", exact: "4.0.3"),
        .package(url: "https://github.com/cyberbanksy/AetherEngine", revision: "1fa363a92a4e4ded0e54c7c2830009a7c371dee4"),
    ],
    targets: [
        .target(
            name: "OpenStreamApple",
            dependencies: [
                .product(
                    name: "AMSMB2",
                    package: "AMSMB2",
                    condition: .when(platforms: [.iOS, .macOS, .tvOS])
                ),
                .product(
                    name: "AetherEngine",
                    package: "AetherEngine"
                ),
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy"),
                .copy("Resources/ChannelLineup"),
                .copy("Resources/ThirdPartyLicenses"),
                .copy("Resources/ThirdPartyNotices"),
                .copy("Resources/Attribution"),
            ]
        ),
        .testTarget(name: "OpenStreamAppleTests", dependencies: ["OpenStreamApple"]),
    ]
)
