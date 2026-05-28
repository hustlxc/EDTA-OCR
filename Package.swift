// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EDTAOCR",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "EDTAOCR",
            path: "Sources/EDTAOCR",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
