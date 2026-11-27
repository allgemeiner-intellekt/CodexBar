// swift-tools-version: 6.0
import PackageDescription

var targets: [Target] = [
    .target(name: "CodexBarCore"),
    .testTarget(name: "QuotaTests", dependencies: ["CodexBarCore"]),
]
#if os(macOS)
targets.append(.executableTarget(name: "CodexBar", dependencies: ["CodexBarCore"]))
#endif

let package = Package(name: "PersonalCodexBar", platforms: [.macOS(.v14)], targets: targets)
