// swift-tools-version: 6.0
import PackageDescription

// Info.plist (LSUIElement = YES) wird zusätzlich direkt ins Binary eingebettet,
// damit die App auch per `swift run` ohne Dock-Icon startet.
let infoPlistPath = Context.packageDirectory + "/Resources/Info.plist"

let package = Package(
    name: "ServerPulse",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ServerPulse",
            path: "Sources/ServerPulse",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlistPath
                ])
            ]
        )
    ]
)
