// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperMic",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "WhisperMic",
            path: "Sources/WhisperMic",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/WhisperMic/Info.plist",
                ]),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
