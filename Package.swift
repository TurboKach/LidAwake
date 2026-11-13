// swift-tools-version: 5.7
import PackageDescription
import Foundation

let package = Package(
    name: "LidAwake",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "LidAwake", targets: ["LidAwake"])],
    targets: [
        .target(name: "LidAwakeCore"),
        .executableTarget(name: "LidAwake", dependencies: ["LidAwakeCore"], path: ".",
            exclude: ["Sources", "Tests", "scripts", "docs", "Localization", "README.md", "TODO.md",
                      "AppIcon.icns", "build.sh", "release.sh", "make-icon.sh", "Info.plist",
                      "LidAwake.app", "LidAwake.dmg", "LidAwake", "dmg-staging", "rw.dmg"]
                .filter { FileManager.default.fileExists(atPath: $0) },
            sources: ["LidAwake.swift"]),
        .testTarget(name: "LidAwakeCoreTests", dependencies: ["LidAwakeCore"])
    ]
)
