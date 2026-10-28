// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SunMemo",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.1")
    ],
    targets: [
        // Resources holds the translations. scripts/build-app.sh copies them
        // into the app, so SwiftPM leaves them alone.
        .executableTarget(name: "SunMemo", dependencies: [
            .product(name: "Sparkle", package: "Sparkle")
        ], path: "Sources/SunMemo", exclude: ["Resources"],
        linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])])
    ]
)
