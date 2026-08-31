// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hulpje",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Hulpje",
            path: "Sources/Hulpje",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Hulpje/Info.plist",
                ]),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
