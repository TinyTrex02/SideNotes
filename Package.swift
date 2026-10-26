// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SideNotes",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "SideNotes", path: "Sources/SideNotes")
    ]
)
