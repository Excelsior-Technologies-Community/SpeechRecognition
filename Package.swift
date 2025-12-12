import PackageDescription

let package = Package(
    name: "SpeechRecognition",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "SpeechToText",
            targets: ["SpeechToText"]
        ),
    ],
    targets: [
        .target(
            name: "SpeechToText",
            dependencies: [],
            path: "Sources/SpeechToText",
            resources: []
        )
    ]
)
