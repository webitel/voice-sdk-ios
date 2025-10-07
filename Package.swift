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
        .package(url: "https://github.com/webitel/ios-pjsipkit.git", from: "0.1.1")
    ],
    targets: [
        .target(
            name: "VoiceSDK",
            dependencies: [
                .product(name: "PJSIPKit", package: "ios-pjsipkit")
            ],
            path: "Sources/VoiceSDK"
        )
    ]
)

