// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription


let package = Package(
    name: "VoiceSDK",
    platforms: [.iOS(.v13)],
    products: [
        .library(
            name: "VoiceSDK",
            targets: ["VoiceSDK"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/webitel/ios-pjsipkit.git",
            exact: "0.3.1"
        ),
        .package(
            url: "https://github.com/apple/swift-log.git",
            from: "1.4.0"
        )
    ],
    targets: [
        .target(
            name: "VoiceSDK",
            dependencies: [
                .product(name: "PJSIPKit", package: "ios-pjsipkit"),
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/VoiceSDK"
        )
    ]
)

